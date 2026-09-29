const path = require("node:path");
module.exports = { apps: [{ name: "rumba-ex-ml-worker", script: path.join(__dirname, "rumba-ex-ml-worker.js"), cwd: __dirname, instances: 1, exec_mode: "fork", autorestart: true, max_restarts: 10, restart_delay: 5000, time: true, env: { NODE_ENV: "production" } }] };
