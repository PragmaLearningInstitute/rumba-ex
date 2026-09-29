const express = require("express");
const {
  clearTokenCache,
  directusFetch,
  extractData,
  getBearerToken,
  validateDirectusToken,
  validateTokenString
} = require("../middleware/auth");

const router = express.Router();
router.use(require("../middleware/rateLimit").createRateLimiter({ max: 20 }));

router.post("/login", async (req, res, next) => {
  try {
    const { email, password } = req.body || {};
    if (!isEmail(email) || typeof password !== "string" || password.length < 1) {
      return res.status(400).json({ error: "Email ou mot de passe invalide." });
    }

    const payload = await directusFetch("/auth/login", {
      method: "POST",
      body: {
        email,
        password,
        mode: "json"
      }
    });
    const data = extractData(payload) || {};
    const accessToken = data.access_token;
    const refreshToken = data.refresh_token;
    let userId = data.user && data.user.id;

    if (accessToken && !userId) {
      try {
        const user = await validateTokenString(accessToken);
        userId = user.id;
      } catch (_error) {
        userId = null;
      }
    }

    return res.json({
      access_token: accessToken,
      refresh_token: refreshToken,
      user_id: userId || null
    });
  } catch (error) {
    return handleDirectusRouteError(error, res, next);
  }
});

router.post("/logout", validateDirectusToken, async (req, res) => {
  const token = getBearerToken(req);

  try {
    await directusFetch("/auth/logout", {
      method: "POST",
      token,
      body: req.body && req.body.refresh_token ? { refresh_token: req.body.refresh_token } : {}
    });
  } catch (error) {
    console.warn("[rumba-ex-api] logout Directus non bloquant", {
      status: error.status,
      message: error.message
    });
  }

  clearTokenCache(token);
  return res.json({ ok: true });
});

router.post("/register", async (req, res, next) => {
  if (process.env.RUMBA_EX_ALLOW_REGISTRATION !== "true" || !process.env.RUMBA_EX_DIRECTUS_ROLE_ID) {
    return res.status(403).json({ error: "Inscription désactivée. Contactez l'administrateur de cette instance." });
  }
  try {
    const { email, password, first_name: firstName } = req.body || {};
    if (!isEmail(email) || typeof password !== "string" || password.length < 8) {
      return res.status(400).json({ error: "Email invalide ou mot de passe trop court." });
    }

    const body = {
      email,
      password,
      status: process.env.RUMBA_EX_NEW_USER_STATUS || "active"
    };

    if (typeof firstName === "string" && firstName.trim()) {
      body.first_name = firstName.trim().slice(0, 100);
    }

    if (process.env.RUMBA_EX_DIRECTUS_ROLE_ID) {
      body.role = process.env.RUMBA_EX_DIRECTUS_ROLE_ID;
    }

    const payload = await directusFetch("/users", {
      method: "POST",
      admin: true,
      body
    });
    const user = extractData(payload);

    return res.status(201).json({
      user_id: user && user.id
    });
  } catch (error) {
    return handleDirectusRouteError(error, res, next);
  }
});

router.get("/me", validateDirectusToken, (req, res) => {
  return res.json({
    id: req.directusUser.id,
    email: req.directusUser.email || null,
    first_name: req.directusUser.first_name || null
  });
});

function handleDirectusRouteError(error, res, next) {
  if (error && (error.status === 400 || error.status === 401 || error.status === 403 || error.status === 409)) {
    return res.status(error.status).json({ error: "Operation Directus refusee." });
  }
  return next(error);
}

function isEmail(value) {
  return typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

module.exports = router;
