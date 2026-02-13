import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";

import { config } from "./config.js";
import { buildPaymentConfig } from "./x402.js";
import { poolRoutes } from "./routes/pools.js";
import { referrerRoutes } from "./routes/referrers.js";
import { agentRoutes } from "./routes/agents.js";
import { optimizeRoutes } from "./routes/optimize.js";

// ============================================================================
// APP SETUP
// ============================================================================

const app = new Hono();

// Global middleware
app.use("*", cors());
app.use("*", logger());

// ============================================================================
// x402 PAYMENT MIDDLEWARE
// ============================================================================

// NOTE: In production, import and use the x402 payment middleware:
//
//   import { paymentMiddleware } from "@x402/server";
//   app.use("*", paymentMiddleware(buildPaymentConfig()));
//
// For development/testing, the middleware is omitted so endpoints are accessible
// without payment. Enable it by uncommenting the line above when deploying.
//
// The payment config is generated from config.ts PRICING table.
const _paymentConfig = buildPaymentConfig();

// ============================================================================
// ROUTES
// ============================================================================

// Health check (free — no x402 payment required)
app.get("/", (c) =>
  c.json({
    service: "FixerHook Referral-as-a-Service (RaaS)",
    version: "1.0.0",
    x402: true,
    endpoints: {
      pools: "/api/v1/pools",
      poolStats: "/api/v1/pools/:id/stats",
      topReferrers: "/api/v1/referrers/top",
      referrerProfile: "/api/v1/referrers/:addr",
      optimizeRoute: "/api/v1/optimize/route?volume=50000&referrer=0x...",
      referralIntent: "POST /api/v1/optimize/referral/intent",
      registerAgent: "POST /api/v1/agents/register",
      agentAnalytics: "/api/v1/agents/analytics/:id",
    },
    pricing: {
      currency: "USDC",
      network: config.x402.network,
      note: "All endpoints are x402-gated. Pay with USDC on Base.",
    },
  })
);

// x402 payment info endpoint (free)
app.get("/api/v1/x402/info", (c) =>
  c.json({
    facilitator: config.x402.facilitatorUrl,
    network: config.x402.network,
    asset: config.x402.usdcAddress,
    treasury: config.x402.treasuryAddress,
    paymentConfig: _paymentConfig,
  })
);

// Mount route groups
app.route("/api/v1/pools", poolRoutes);
app.route("/api/v1/referrers", referrerRoutes);
app.route("/api/v1/agents", agentRoutes);
app.route("/api/v1/optimize", optimizeRoutes);

// ============================================================================
// SERVER
// ============================================================================

console.log(`
╔══════════════════════════════════════════════════════════╗
║         FixerHook RaaS Server (x402-enabled)            ║
╠══════════════════════════════════════════════════════════╣
║  Port:     ${String(config.port).padEnd(44)}║
║  Network:  ${config.x402.network.padEnd(44)}║
║  Registry: ${(config.chain.registryAddress ?? "not set").slice(0, 44).padEnd(44)}║
║  x402:     ${(config.x402.facilitatorUrl ?? "not set").slice(0, 44).padEnd(44)}║
╚══════════════════════════════════════════════════════════╝
`);

serve({
  fetch: app.fetch,
  port: config.port,
});
