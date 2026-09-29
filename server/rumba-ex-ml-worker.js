#!/usr/bin/env node
import { spawn } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { Client } from "pg";
import { fileURLToPath } from "node:url";

const DEFAULT_DB_URL = "postgresql://localhost/rumba_dev";
const APP_DIR = process.env.RUMBA_EX_APP_DIR || dirname(fileURLToPath(import.meta.url));
const PIPELINE_SCRIPT = process.env.RUMBA_ML_PIPELINE_SCRIPT || "rumba_ml_pipeline.py";
const PYTHON_BIN = process.env.RUMBA_ML_PYTHON || "python3";
const CHANNEL = process.env.RUMBA_ML_NOTIFY_CHANNEL || "exercise_changed";
const LOG_PATH = process.env.RUMBA_ML_WORKER_LOG_PATH || join(APP_DIR, "ml_worker.log");
const PIPELINE_LOG_PATH = process.env.RUMBA_ML_LOG_PATH || join(APP_DIR, "ml_pipeline.log");
const DEBOUNCE_MS = Number(process.env.RUMBA_ML_DEBOUNCE_MS || 60000);
const RECONNECT_MS = Number(process.env.RUMBA_ML_RECONNECT_MS || 5000);

let client = null;
let debounceTimer = null;
let reconnectTimer = null;
let running = false;
let rerunRequested = false;
let stopped = false;
const pendingExerciseIds = new Set();

function ensureLogDirectory() {
  try {
    mkdirSync(dirname(LOG_PATH), { recursive: true });
  } catch (error) {
    console.warn("[rumba-ex-ml-worker] impossible de creer le dossier de log", error.message);
  }
}

function log(message, metadata = undefined) {
  const suffix = metadata === undefined ? "" : ` ${JSON.stringify(metadata)}`;
  const line = `${new Date().toISOString()} ${message}${suffix}\n`;
  try {
    appendFileSync(LOG_PATH, line);
  } catch {
    console.log(line.trimEnd());
  }
}

function makeClient() {
  if (process.env.RUMBA_DB_URL) {
    return new Client({
      connectionString: process.env.RUMBA_DB_URL,
      application_name: "rumba-ex-ml-worker"
    });
  }

  return new Client({
    connectionString: DEFAULT_DB_URL,
    host: process.env.PGHOST || undefined,
    port: process.env.PGPORT ? Number(process.env.PGPORT) : undefined,
    user: process.env.PGUSER || undefined,
    password: process.env.PGPASSWORD || undefined,
    database: process.env.PGDATABASE || undefined,
    application_name: "rumba-ex-ml-worker"
  });
}

function quoteIdentifier(identifier) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(identifier)) {
    throw new Error(`Nom de canal PostgreSQL invalide: ${identifier}`);
  }
  return `"${identifier.replaceAll('"', '""')}"`;
}

async function connectAndListen() {
  if (stopped) return;

  clearTimeout(reconnectTimer);
  reconnectTimer = null;

  try {
    client = makeClient();
    client.on("notification", handleNotification);
    client.on("error", (error) => {
      log("Erreur PostgreSQL listener", { message: error.message, code: error.code });
      scheduleReconnect();
    });
    client.on("end", () => {
      log("Connexion PostgreSQL listener fermee");
      scheduleReconnect();
    });

    await client.connect();
    await client.query(`LISTEN ${quoteIdentifier(CHANNEL)}`);
    log("Worker RUMBA.EX ML en ecoute", { channel: CHANNEL, debounce_ms: DEBOUNCE_MS });
  } catch (error) {
    log("Echec connexion PostgreSQL listener", { message: error.message });
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  if (stopped || reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectAndListen().catch((error) => {
      log("Erreur reconnexion listener", { message: error.message });
      scheduleReconnect();
    });
  }, RECONNECT_MS);
}

function handleNotification(notification) {
  if (notification.channel !== CHANNEL) return;
  if (notification.payload) {
    pendingExerciseIds.add(notification.payload);
  }
  log("Notification exercise_changed recue", {
    exercise_id: notification.payload || null,
    pending_count: pendingExerciseIds.size
  });
  schedulePipelineRun();
}

function schedulePipelineRun() {
  if (stopped) return;
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(runPipeline, DEBOUNCE_MS);
}

function pipeToLog(stream, label) {
  stream.on("data", (chunk) => {
    String(chunk)
      .split(/\r?\n/)
      .filter(Boolean)
      .forEach((line) => log(`${label}: ${line}`));
  });
}

function runPipeline() {
  if (running) {
    rerunRequested = true;
    log("Pipeline deja en cours, relance demandee apres execution");
    return;
  }

  running = true;
  rerunRequested = false;
  const exerciseIds = Array.from(pendingExerciseIds);
  pendingExerciseIds.clear();

  log("Demarrage pipeline ML RUMBA.EX", {
    exercise_count: exerciseIds.length,
    app_dir: APP_DIR,
    script: PIPELINE_SCRIPT
  });

  const child = spawn(PYTHON_BIN, [PIPELINE_SCRIPT], {
    cwd: APP_DIR,
    env: {
      ...process.env,
      RUMBA_ML_LOG_PATH: PIPELINE_LOG_PATH
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  pipeToLog(child.stdout, "pipeline stdout");
  pipeToLog(child.stderr, "pipeline stderr");

  child.on("error", (error) => {
    running = false;
    log("Erreur lancement pipeline ML", { message: error.message });
    if (pendingExerciseIds.size || rerunRequested) schedulePipelineRun();
  });

  child.on("close", (code, signal) => {
    running = false;
    log("Pipeline ML termine", { code, signal });
    if (pendingExerciseIds.size || rerunRequested) {
      schedulePipelineRun();
    }
  });
}

async function shutdown(signal) {
  stopped = true;
  clearTimeout(debounceTimer);
  clearTimeout(reconnectTimer);
  log("Arret worker RUMBA.EX ML", { signal });
  try {
    if (client) {
      await client.end();
    }
  } catch (error) {
    log("Erreur fermeture PostgreSQL listener", { message: error.message });
  }
  process.exit(0);
}

ensureLogDirectory();
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("uncaughtException", (error) => {
  log("Exception non capturee", { message: error.message, stack: error.stack });
  process.exit(1);
});
process.on("unhandledRejection", (error) => {
  log("Promise rejetee non capturee", { message: error?.message || String(error) });
  process.exit(1);
});

connectAndListen();
