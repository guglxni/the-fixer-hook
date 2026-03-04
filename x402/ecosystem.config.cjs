/**
 * PM2 Ecosystem Config for FixerHook backend services
 *
 * Services deployed:
 *   1. raas-server  — Hono HTTP API, port 3402, x402-gated
 *   2. xmtp-bot     — XMTP listener / referral messaging bot
 *   3. mcp-server   — MCP (stdio) server for AI agent tooling
 *
 * Usage on server:
 *   pm2 start ecosystem.config.cjs
 *   pm2 save
 *   pm2 startup
 */

module.exports = {
  apps: [
    // ──────────────────────────────────────────────
    // 1. RaaS HTTP API (Hono + x402)
    // ──────────────────────────────────────────────
    {
      name: "raas-server",
      script: "dist/index.js",
      cwd: "/opt/fixerhook/raas-server",
      interpreter: "node",
      instances: 1,
      exec_mode: "fork",
      env_file: "/opt/fixerhook/raas-server/.env",
      env: {
        NODE_ENV: "production",
        PORT: "3402",
      },
      // Auto-restart on crash, memory limit 256 MB
      max_memory_restart: "256M",
      restart_delay: 3000,
      exp_backoff_restart_delay: 100,
      // Logging
      out_file: "/var/log/fixerhook/raas-server.out.log",
      error_file: "/var/log/fixerhook/raas-server.err.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    },

    // ──────────────────────────────────────────────
    // 2. XMTP Bot (background listener)
    // ──────────────────────────────────────────────
    {
      name: "xmtp-bot",
      script: "dist/index.js",
      cwd: "/opt/fixerhook/xmtp-bot",
      interpreter: "node",
      instances: 1,
      exec_mode: "fork",
      env_file: "/opt/fixerhook/xmtp-bot/.env",
      env: {
        NODE_ENV: "production",
      },
      max_memory_restart: "256M",
      restart_delay: 5000,
      exp_backoff_restart_delay: 200,
      out_file: "/var/log/fixerhook/xmtp-bot.out.log",
      error_file: "/var/log/fixerhook/xmtp-bot.err.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    },

    // ──────────────────────────────────────────────
    // 3. MCP Server (stdio — run on-demand or via socat bridge)
    //    NOTE: stdio MCP servers are NOT meant to be long-running
    //    HTTP services. This entry keeps it as a managed process
    //    when using the SSE HTTP transport (see notes in mcp-server/).
    //    For pure local/Claude Desktop use, skip this entry and
    //    use the npx invocation documented in mcp-server/README.md.
    // ──────────────────────────────────────────────
    {
      name: "mcp-server",
      script: "dist/index.js",
      cwd: "/opt/fixerhook/mcp-server",
      interpreter: "node",
      instances: 1,
      exec_mode: "fork",
      env_file: "/opt/fixerhook/mcp-server/.env",
      env: {
        NODE_ENV: "production",
        // Set to "http" to enable SSE transport on MCP_PORT (default 3403)
        MCP_TRANSPORT: "http",
        MCP_PORT: "3403",
      },
      max_memory_restart: "128M",
      restart_delay: 5000,
      out_file: "/var/log/fixerhook/mcp-server.out.log",
      error_file: "/var/log/fixerhook/mcp-server.err.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    },
  ],
};
