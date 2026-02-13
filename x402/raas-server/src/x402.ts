import { config, PRICING } from "./config.js";

/**
 * Build an x402 paymentMiddleware-compatible configuration object.
 *
 * Each key is a route pattern (METHOD /path) and each value defines
 * the x402 payment terms the client must satisfy.
 *
 * @see https://docs.cdp.coinbase.com/x402/docs/welcome
 */
export function buildPaymentConfig(): Record<string, unknown> {
  const entries: Record<string, unknown> = {};

  for (const [route, amount] of Object.entries(PRICING)) {
    entries[route] = {
      accepts: [
        {
          scheme: "exact",
          network: config.x402.network,          // eip155:8453 (Base)
          maxAmountRequired: amount,              // USDC atomic (6 decimals)
          resource: routeDescription(route),
          payTo: config.x402.treasuryAddress,
          asset: config.x402.usdcAddress,
        },
      ],
      description: routeDescription(route),
    };
  }

  return entries;
}

/** Human-readable description for each route */
function routeDescription(route: string): string {
  const descriptions: Record<string, string> = {
    "GET /api/v1/pools": "List of active FixerHook pools with reward parameters",
    "GET /api/v1/pools/:id/stats": "Detailed pool statistics including volume and referral count",
    "GET /api/v1/referrers/top": "Top referrers by tier with performance metrics",
    "GET /api/v1/referrers/:addr": "Full referrer profile with earnings, tier, and history",
    "GET /api/v1/optimize/route": "AI-optimized swap route for maximum referral reward",
    "POST /api/v1/referral/intent": "Submit a referral intent with pre-signed hookData",
    "GET /api/v1/analytics/agent/:id": "Agent-specific analytics dashboard data",
    "POST /api/v1/agents/register": "Register an AI agent as a verified referrer ($1 USDC)",
  };
  return descriptions[route] ?? route;
}
