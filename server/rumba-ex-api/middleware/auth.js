const DIRECTUS_URL = trimTrailingSlash(process.env.DIRECTUS_URL || "http://127.0.0.1:8055");
const DIRECTUS_ADMIN_TOKEN = process.env.DIRECTUS_ADMIN_TOKEN || "";
const TOKEN_CACHE_MS = 60 * 1000;
const tokenCache = new Map();

function getBearerToken(req) {
  const header = req.headers.authorization || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

async function validateDirectusToken(req, res, next) {
  const token = getBearerToken(req);

  try {
    const user = await validateTokenString(token);
    req.directusToken = token;
    req.directusUser = user;
    req.userId = user.id;
    return next();
  } catch (_error) {
    return res.status(401).json({ error: "Token invalide ou expire." });
  }
}

async function validateTokenString(token) {
  if (!token || token === "guest") {
    const error = new Error("Missing user token");
    error.status = 401;
    throw error;
  }

  const cached = tokenCache.get(token);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.user;
  }

  const payload = await directusFetch("/users/me", {
    token,
    query: {
      fields: "id,email,first_name"
    }
  });
  const user = extractData(payload);

  if (!user || !user.id) {
    const error = new Error("Invalid Directus token payload");
    error.status = 401;
    throw error;
  }

  for (const [key, value] of tokenCache) {
    if (value.expiresAt <= Date.now()) tokenCache.delete(key);
  }
  if (tokenCache.size >= 2000) tokenCache.delete(tokenCache.keys().next().value);
  tokenCache.set(token, {
    user,
    expiresAt: Date.now() + TOKEN_CACHE_MS
  });
  return user;
}

async function directusFetch(path, options = {}) {
  const {
    method = "GET",
    token = null,
    admin = false,
    body = undefined,
    query = undefined
  } = options;
  const url = path.startsWith("http") ? new URL(path) : new URL(`${DIRECTUS_URL}${path}`);

  if (query && typeof query === "object") {
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, String(value));
      }
    }
  }

  const headers = {
    Accept: "application/json"
  };

  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }

  if (admin) {
    if (!DIRECTUS_ADMIN_TOKEN) {
      const error = new Error("DIRECTUS_ADMIN_TOKEN missing");
      error.status = 500;
      throw error;
    }
    headers.Authorization = `Bearer ${DIRECTUS_ADMIN_TOKEN}`;
  } else if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(url, {
    method,
    signal: AbortSignal.timeout(15000),
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const responseText = await response.text();
  const parsed = parseJson(responseText);

  if (!response.ok) {
    const error = new Error(`Directus request failed: ${method} ${url.pathname}`);
    error.status = response.status;
    error.data = parsed || responseText;
    throw error;
  }

  return parsed;
}

function extractData(payload) {
  if (!payload || typeof payload !== "object") return payload;
  return Object.prototype.hasOwnProperty.call(payload, "data") ? payload.data : payload;
}

function clearTokenCache(token) {
  if (token) tokenCache.delete(token);
}

function trimTrailingSlash(value) {
  return String(value || "").replace(/\/+$/, "");
}

function parseJson(value) {
  if (!value) return null;
  try {
    return JSON.parse(value);
  } catch (_error) {
    return null;
  }
}

module.exports = {
  DIRECTUS_URL,
  getBearerToken,
  validateDirectusToken,
  validateTokenString,
  directusFetch,
  extractData,
  clearTokenCache
};
