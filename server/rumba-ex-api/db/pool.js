const { Pool } = require("pg");

const pool = new Pool({
  host: process.env.PGHOST || "127.0.0.1",
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || require("node:os").userInfo().username,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE || "rumba_dev",
  max: Number(process.env.PGPOOL_MAX || 10),
  idleTimeoutMillis: Number(process.env.PGPOOL_IDLE_TIMEOUT_MS || 30000),
  connectionTimeoutMillis: Number(process.env.PGPOOL_CONNECTION_TIMEOUT_MS || 5000)
});

pool.on("error", (error) => {
  console.error("[rumba-ex-api] erreur pool PostgreSQL", {
    message: error.message,
    code: error.code
  });
});

module.exports = pool;
