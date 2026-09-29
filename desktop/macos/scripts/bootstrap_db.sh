#!/usr/bin/env bash
set -euo pipefail
: "${RUMBA_DB_URL:?Set RUMBA_DB_URL to a dedicated development database}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$APP_DIR/../.." && pwd)"
psql -v ON_ERROR_STOP=1 "$RUMBA_DB_URL" -f "$ROOT_DIR/schema/000_development.sql"
psql -v ON_ERROR_STOP=1 "$RUMBA_DB_URL" -f "$ROOT_DIR/schema/001_embeddings.sql"
psql -v ON_ERROR_STOP=1 "$RUMBA_DB_URL" -f "$APP_DIR/sql/01_app_backend.sql"
