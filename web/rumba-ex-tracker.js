const DIRECTUS_URL = (typeof window !== "undefined" && window.__PLI_DIRECTUS_URL__)
  || "";

let sessionId = null;

function createSessionId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  const bytes = new Uint8Array(16);
  if (globalThis.crypto && typeof globalThis.crypto.getRandomValues === "function") {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10, 16).join("")}`;
}

function getSessionId() {
  if (!sessionId) sessionId = createSessionId();
  return sessionId;
}

function bucket(age) {
  const value = Number(age);
  if (!Number.isFinite(value)) return null;
  if (value <= 8) return "6-8";
  if (value <= 11) return "9-11";
  return "12-14";
}

function integerOrNull(value) {
  const number = Number.parseInt(value, 10);
  return Number.isFinite(number) ? number : null;
}

function normalizeFormat(format) {
  const normalized = String(format || "").toLowerCase();
  return ["html", "pdf", "docx"].includes(normalized) ? normalized : null;
}

function postEvent(payload) {
  if (typeof window === "undefined" || window.RUMBA_TELEMETRY_ENABLED !== true) return;
  const baseUrl = String(DIRECTUS_URL || "").replace(/\/+$/, "");
  if (!baseUrl || typeof fetch !== "function") return;

  fetch(`${baseUrl}/items/rumba_ex_events`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      event_type: payload.event_type,
      session_id: getSessionId(),
      age_range: payload.age_range ?? null,
      blockers_count: integerOrNull(payload.blockers_count),
      exercise_count: integerOrNull(payload.exercise_count),
      export_format: normalizeFormat(payload.export_format),
      is_guest: Boolean(payload.is_guest),
    }),
    keepalive: true,
  }).catch(() => {});
}

export function initTracker() {
  sessionId = createSessionId();
  return sessionId;
}

export function trackConnectedSession() {
  postEvent({
    event_type: "session_start",
    is_guest: false,
  });
}

export function trackProfileCreated({ blockersCount, age } = {}) {
  postEvent({
    event_type: "profile_created",
    age_range: bucket(age),
    blockers_count: blockersCount,
    is_guest: false,
  });
}

export function trackGuestSession() {
  postEvent({
    event_type: "session_start",
    is_guest: true,
  });
}

export function trackRecommendation({ blockersCount, exerciseCount, isGuest = false } = {}) {
  postEvent({
    event_type: "recommendation_generated",
    blockers_count: blockersCount,
    exercise_count: exerciseCount,
    is_guest: isGuest,
  });
}

export function trackExport({ format, isGuest = false } = {}) {
  postEvent({
    event_type: "export",
    export_format: format,
    is_guest: isGuest,
  });
}
