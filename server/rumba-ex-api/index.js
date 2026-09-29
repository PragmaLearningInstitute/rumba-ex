require("dotenv").config();

const express = require("express");
const authRoutes = require("./routes/auth");
const profileRoutes = require("./routes/profiles");
const recommendRoutes = require("./routes/recommend");

const app = express();
const port = Number(process.env.PORT || 3001);

// Only trust explicitly configured proxy addresses, never arbitrary forwarded headers.
const trustedProxies = (process.env.TRUST_PROXY || "").split(",").map(x => x.trim()).filter(Boolean);
app.set("trust proxy", trustedProxies.length ? trustedProxies : false);

app.use(corsMiddleware);
app.use(express.json({ limit: "128kb" }));

app.get(["/rumba-ex/api/health", "/health"], (_req, res) => {
  res.json({ ok: true, service: "rumba-ex-api" });
});

app.use("/rumba-ex/api/auth", authRoutes);
app.use("/rumba-ex/api/profiles", profileRoutes);
app.use("/rumba-ex/api/recommend", recommendRoutes);

// Keep local development usable if a reverse proxy strips /rumba-ex/api.
app.use("/auth", authRoutes);
app.use("/profiles", profileRoutes);
app.use("/recommend", recommendRoutes);

if (process.env.SERVE_WEB === "true") {
  app.use(express.static(require("node:path").resolve(__dirname, "../../web"), { dotfiles: "deny" }));
}

app.use((_req, res) => {
  res.status(404).json({ error: "Endpoint introuvable." });
});

app.use((err, _req, res, _next) => {
  if (err && err.type === "entity.parse.failed") {
    return res.status(400).json({ error: "Corps JSON invalide." });
  }

  const status = Number(err && err.status) || 500;
  if (status >= 500) {
    console.error("[rumba-ex-api] erreur interne", {
      message: err && err.message,
      code: err && err.code
    });
  }

  return res.status(status >= 400 && status < 500 ? status : 500).json({
    error: status >= 500 ? "Erreur interne du serveur." : (err && err.publicMessage) || "Requete invalide."
  });
});

app.listen(port, process.env.HOST || "127.0.0.1", () => {
  console.log(`[rumba-ex-api] ecoute sur le port ${port}`);
});

function corsMiddleware(req, res, next) {
  const configuredOrigins = (process.env.CORS_ORIGIN || "http://127.0.0.1:3001")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  const origin = req.headers.origin;

  if (!origin || configuredOrigins.includes(origin)) {
    if (origin) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
    }
    res.setHeader("Access-Control-Allow-Credentials", "true");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  }

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  return next();
}
