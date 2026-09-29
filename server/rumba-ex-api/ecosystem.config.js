module.exports = {
  apps: [
    {
      name: "rumba-ex-api",
      script: "index.js",
      instances: 1,
      exec_mode: "fork",
      env: {
        NODE_ENV: "production",
        PORT: process.env.PORT || 3001
      }
    }
  ]
};
