#!/usr/bin/env bash
set -Eeuo pipefail

# Configure these values before running:
#   DIRECTUS_URL="http://127.0.0.1:8055"
#   DIRECTUS_ADMIN_TOKEN="..."
DIRECTUS_URL="${DIRECTUS_URL:-http://127.0.0.1:8055}"
DIRECTUS_ADMIN_TOKEN="${DIRECTUS_ADMIN_TOKEN:-}"

SCHEMA_FILE="${SCHEMA_FILE:-rumba-ex-directus-schema.json}"
AUTH_ROLE_NAME="${RUMBA_EX_AUTH_ROLE_NAME:-RUMBA.EX Authenticated User}"
AUTH_POLICY_NAME="${RUMBA_EX_AUTH_POLICY_NAME:-RUMBA.EX Authenticated User Policy}"
SERVICE_ROLE_NAME="${RUMBA_EX_SERVICE_ROLE_NAME:-RUMBA.EX ML Pipeline Service}"
SERVICE_POLICY_NAME="${RUMBA_EX_SERVICE_POLICY_NAME:-RUMBA.EX ML Pipeline Service Policy}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to apply this Directus schema." >&2
  exit 1
fi

if [[ -z "${DIRECTUS_ADMIN_TOKEN}" ]]; then
  echo "Set DIRECTUS_ADMIN_TOKEN before running this script." >&2
  exit 1
fi

if [[ ! -f "${SCHEMA_FILE}" ]]; then
  echo "Schema file not found: ${SCHEMA_FILE}" >&2
  exit 1
fi

DIRECTUS_URL="${DIRECTUS_URL%/}"

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -g -fsS \
    -X "${method}" \
    -H "Authorization: Bearer ${DIRECTUS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@" \
    "${DIRECTUS_URL}${path}"
}

urlencode() {
  jq -rn --arg value "$1" '$value|@uri'
}

json_post() {
  local path="$1"
  local body="$2"
  api POST "${path}" --data-binary "${body}"
}

json_patch() {
  local path="$1"
  local body="$2"
  api PATCH "${path}" --data-binary "${body}"
}

first_id() {
  jq -r '.data[0].id // empty'
}

apply_schema() {
  local tmp_schema
  tmp_schema="$(mktemp)"
  trap 'rm -f "${tmp_schema}"' RETURN

  jq 'del(.x_rumba_ex_permissions)' "${SCHEMA_FILE}" > "${tmp_schema}"

  echo "[rumba-ex] Computing Directus schema diff..."
  local diff_response
  diff_response="$(api POST "/schema/diff?force=true" --data-binary @"${tmp_schema}")"

  local has_diff
  has_diff="$(printf '%s' "${diff_response}" | jq -r 'if (.data.diff // null) == null then "no" elif (.data.diff | type) == "array" and (.data.diff | length) == 0 then "no" else "yes" end')"

  if [[ "${has_diff}" == "no" ]]; then
    echo "[rumba-ex] Schema already up to date."
    return
  fi

  echo "[rumba-ex] Applying Directus schema diff..."
  printf '%s' "${diff_response}" | jq -c '.data' | api POST "/schema/apply" --data-binary @-
  echo "[rumba-ex] Schema applied."
}

ensure_role() {
  local name="$1"
  local icon="$2"
  local description="$3"
  local encoded
  encoded="$(urlencode "${name}")"

  local existing
  existing="$(api GET "/roles?filter[name][_eq]=${encoded}&fields=id,name&limit=1" | first_id)"
  if [[ -n "${existing}" ]]; then
    echo "${existing}"
    return
  fi

  json_post "/roles" "$(jq -n \
    --arg name "${name}" \
    --arg icon "${icon}" \
    --arg description "${description}" \
    '{name:$name,icon:$icon,description:$description}')" | jq -r '.data.id'
}

ensure_policy() {
  local name="$1"
  local icon="$2"
  local description="$3"
  local app_access="${4:-false}"
  local encoded
  encoded="$(urlencode "${name}")"

  local existing
  existing="$(api GET "/policies?filter[name][_eq]=${encoded}&fields=id,name&limit=1" | first_id)"
  if [[ -n "${existing}" ]]; then
    json_patch "/policies/${existing}" "$(jq -n \
      --arg name "${name}" \
      --arg icon "${icon}" \
      --arg description "${description}" \
      --argjson app_access "${app_access}" \
      '{name:$name,icon:$icon,description:$description,admin_access:false,app_access:$app_access,enforce_tfa:false}')" >/dev/null
    echo "${existing}"
    return
  fi

  json_post "/policies" "$(jq -n \
    --arg name "${name}" \
    --arg icon "${icon}" \
    --arg description "${description}" \
    --argjson app_access "${app_access}" \
    '{name:$name,icon:$icon,description:$description,admin_access:false,app_access:$app_access,enforce_tfa:false}')" | jq -r '.data.id'
}

ensure_access() {
  local role_id="$1"
  local policy_id="$2"

  local existing
  existing="$(api GET "/access?filter[role][_eq]=${role_id}&filter[policy][_eq]=${policy_id}&fields=id&limit=1" | first_id)"
  if [[ -n "${existing}" ]]; then
    return
  fi

  json_post "/access" "$(jq -n \
    --arg role "${role_id}" \
    --arg policy "${policy_id}" \
    '{role:$role,policy:$policy}')" >/dev/null
}

public_policy_id() {
  local policy
  policy="$(api GET "/access?filter[role][_null]=true&filter[user][_null]=true&fields=policy&limit=1" | jq -r '.data[0].policy // empty')"
  if [[ -z "${policy}" ]]; then
    echo "Could not find Directus public policy through /access." >&2
    exit 1
  fi
  echo "${policy}"
}

ensure_permission() {
  local policy_id="$1"
  local collection="$2"
  local action="$3"
  local fields_json="$4"
  local permissions_json="$5"
  local validation_json="$6"
  local presets_json="$7"

  local existing
  existing="$(api GET "/permissions?filter[policy][_eq]=${policy_id}&filter[collection][_eq]=${collection}&filter[action][_eq]=${action}&fields=id&limit=1" | first_id)"

  local body
  body="$(jq -n \
    --arg policy "${policy_id}" \
    --arg collection "${collection}" \
    --arg action "${action}" \
    --argjson fields "${fields_json}" \
    --argjson permissions "${permissions_json}" \
    --argjson validation "${validation_json}" \
    --argjson presets "${presets_json}" \
    '{policy:$policy,collection:$collection,action:$action,fields:$fields,permissions:$permissions,validation:$validation,presets:$presets}')"

  if [[ -n "${existing}" ]]; then
    json_patch "/permissions/${existing}" "${body}" >/dev/null
  else
    json_post "/permissions" "${body}" >/dev/null
  fi
}

apply_permissions() {
  echo "[rumba-ex] Ensuring roles and policies..."
  local auth_role_id auth_policy_id service_role_id service_policy_id public_policy
  auth_role_id="$(ensure_role "${AUTH_ROLE_NAME}" "school" "Authenticated users allowed to use private RUMBA.EX profiles.")"
  auth_policy_id="$(ensure_policy "${AUTH_POLICY_NAME}" "school" "Row-level access to owned RUMBA.EX profiles and recommendation history." "false")"
  ensure_access "${auth_role_id}" "${auth_policy_id}"

  service_role_id="$(ensure_role "${SERVICE_ROLE_NAME}" "hub" "API-only role for the RUMBA.EX ML pipeline.")"
  service_policy_id="$(ensure_policy "${SERVICE_POLICY_NAME}" "hub" "Service access to write RUMBA.EX exercise metadata." "false")"
  ensure_access "${service_role_id}" "${service_policy_id}"

  public_policy="$(public_policy_id)"

  local profile_fields profile_read_fields profile_validation profile_owner
  profile_fields='["student_name","age","blockers","exercise_target","temperature"]'
  profile_read_fields='["id","user_created","date_created","date_updated","student_name","age","blockers","exercise_target","temperature"]'
  profile_validation='{"_and":[{"age":{"_gte":6}},{"age":{"_lte":14}},{"exercise_target":{"_gte":1}},{"exercise_target":{"_lte":5}},{"temperature":{"_gte":0.1}},{"temperature":{"_lte":3}}]}'
  profile_owner='{"user_created":{"_eq":"$CURRENT_USER"}}'

  ensure_permission "${auth_policy_id}" "rumba_ex_profiles" "create" "${profile_fields}" '{}' "${profile_validation}" '{"user_created":"$CURRENT_USER","exercise_target":3,"temperature":0.8}'
  ensure_permission "${auth_policy_id}" "rumba_ex_profiles" "read" "${profile_read_fields}" "${profile_owner}" '{}' '{}'
  ensure_permission "${auth_policy_id}" "rumba_ex_profiles" "update" "${profile_fields}" "${profile_owner}" "${profile_validation}" '{}'
  ensure_permission "${auth_policy_id}" "rumba_ex_profiles" "delete" '["id"]' "${profile_owner}" '{}' '{}'

  local history_fields history_read_fields history_owner history_validation
  history_fields='["profile_id","exercise_uuid","final_score","relevance_score","authority_score","diversity_score"]'
  history_read_fields='["id","profile_id","exercise_uuid","final_score","relevance_score","authority_score","diversity_score","recommended_at","student_score","student_ease","feedback_updated_at"]'
  history_owner='{"profile_id":{"user_created":{"_eq":"$CURRENT_USER"}}}'
  history_validation='{"profile_id":{"user_created":{"_eq":"$CURRENT_USER"}}}'

  ensure_permission "${auth_policy_id}" "rumba_ex_recommendation_history" "create" "${history_fields}" "${history_owner}" "${history_validation}" '{}'
  ensure_permission "${auth_policy_id}" "rumba_ex_recommendation_history" "read" "${history_read_fields}" "${history_owner}" '{}' '{}'
  ensure_permission "${auth_policy_id}" "rumba_ex_recommendation_history" "delete" '["id"]' "${history_owner}" '{}' '{}'

  local meta_fields
  meta_fields='["exercise_uuid","cluster_id","cluster_label","umap_x","umap_y","nearest_neighbors","last_ml_run"]'
  ensure_permission "${auth_policy_id}" "rumba_ex_exercises_meta" "read" "${meta_fields}" '{}' '{}' '{}'
  ensure_permission "${public_policy}" "rumba_ex_exercises_meta" "read" "${meta_fields}" '{}' '{}' '{}'

  ensure_permission "${service_policy_id}" "rumba_ex_exercises_meta" "create" "${meta_fields}" '{}' '{}' '{}'
  ensure_permission "${service_policy_id}" "rumba_ex_exercises_meta" "read" "${meta_fields}" '{}' '{}' '{}'
  ensure_permission "${service_policy_id}" "rumba_ex_exercises_meta" "update" "${meta_fields}" '{}' '{}' '{}'
  ensure_permission "${service_policy_id}" "rumba_ex_exercises_meta" "delete" '["exercise_uuid"]' '{}' '{}' '{}'

  local event_fields event_validation
  event_fields='["event_type","session_id","age_range","blockers_count","exercise_count","export_format","is_guest"]'
  event_validation='{"event_type":{"_in":["session_start","profile_created","recommendation_generated","exercise_viewed","export","guest_recommendation"]}}'
  ensure_permission "${public_policy}" "rumba_ex_events" "create" "${event_fields}" '{}' "${event_validation}" '{}'

  echo "[rumba-ex] Permissions applied."
  echo "[rumba-ex] Attach '${AUTH_POLICY_NAME}' to any additional existing Directus roles that should use RUMBA.EX."
}

apply_schema
apply_permissions

echo "[rumba-ex] Done."
