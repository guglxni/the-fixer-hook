import "dotenv/config";

/** Server configuration loaded from environment */
export const config = {
  port: Number(process.env.PORT ?? 3402),
  nodeEnv: process.env.NODE_ENV ?? "development",

  // x402 payment configuration
  x402: {
    treasuryAddress: process.env.X402_TREASURY_ADDRESS!,
    usdcAddress: process.env.X402_USDC_ADDRESS ?? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    facilitatorUrl: process.env.X402_FACILITATOR_URL ?? "https://x402.org/facilitator",
    /** CAIP-2 network identifier for Base mainnet */
    network: "eip155:8453",
  },

  // On-chain configuration
  chain: {
    rpcUrl: process.env.RPC_URL ?? "https://mainnet.base.org",
    registryAddress: process.env.REGISTRY_ADDRESS!,
    adminKey: process.env.ADMIN_PRIVATE_KEY,
  },
} as const;

/**
 * x402 pricing table for each endpoint (in USDC atomic units, 6 decimals).
 * Example: "1000" = $0.001 USDC
 */
export const PRICING = {
  "GET /api/v1/pools":               "1000",     // $0.001
  "GET /api/v1/pools/:id/stats":     "5000",     // $0.005
  "GET /api/v1/referrers/top":       "10000",    // $0.01
  "GET /api/v1/referrers/:addr":     "5000",     // $0.005
  "GET /api/v1/optimize/route":      "20000",    // $0.02
  "POST /api/v1/referral/intent":    "50000",    // $0.05
  "GET /api/v1/analytics/agent/:id": "10000",    // $0.01
  "POST /api/v1/agents/register":    "1000000",  // $1.00
} as const;
