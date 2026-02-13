import { Hono } from "hono";
import { type Address, formatUnits, parseUnits } from "viem";
import { getRegistryContract, tierName } from "../chain.js";

/**
 * Optimization routes — x402-gated AI-powered swap routing
 *
 * Enhancement 1 (RaaS API) — Route Optimization
 */
export const optimizeRoutes = new Hono();

// ---------------------------------------------------------------------------
// GET /api/v1/optimize/route — Optimal swap route for max referral reward ($0.02)
// ---------------------------------------------------------------------------
optimizeRoutes.get("/route", async (c) => {
  const volumeStr = c.req.query("volume");
  const referrer = c.req.query("referrer") as Address | undefined;

  if (!volumeStr) {
    return c.json({ error: "Missing required query parameter: volume (in token units)" }, 400);
  }

  const registry = getRegistryContract();
  const volume = parseUnits(volumeStr, 18);

  // Calculate estimated reward
  let estimatedReward = 0n;
  if (referrer) {
    estimatedReward = await registry.read.calculateRewardWithTier([volume, referrer]);
  }

  // In production, this would:
  // 1. Query all active pools from a subgraph
  // 2. Check liquidity depth in each pool
  // 3. Compare reward rates across pools
  // 4. Factor in gas costs and slippage
  // 5. Return the optimal route

  return c.json({
    optimization: {
      inputVolume: volumeStr,
      referrer: referrer ?? "none",
      estimatedReward: referrer ? formatUnits(estimatedReward, 18) : "specify a referrer address",
      strategy: "Route through the pool with highest reward rate for this volume",
    },
    recommendations: [
      "Use a Platinum-tier referrer for 2.0x reward multiplier",
      "Verified x402 agents receive additional bonus multiplier",
      "Minimum swap amount applies — check pool parameters",
    ],
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// POST /api/v1/referral/intent — Submit referral intent ($0.05)
// ---------------------------------------------------------------------------
optimizeRoutes.post("/referral/intent", async (c) => {
  const body = await c.req.json();
  const { referrer, swapper, poolId, estimatedVolume } = body as {
    referrer: Address;
    swapper: Address;
    poolId: string;
    estimatedVolume: string;
  };

  if (!referrer || !swapper || !poolId) {
    return c.json({ error: "Missing required fields: referrer, swapper, poolId" }, 400);
  }

  // In production, this would:
  // 1. Validate the referrer is registered and active
  // 2. Encode the hookData (abi.encode(referrer))
  // 3. Optionally pre-sign the hookData for the swapper
  // 4. Return the prepared transaction data

  return c.json({
    intent: {
      referrer,
      swapper,
      poolId,
      estimatedVolume: estimatedVolume ?? "unknown",
      hookData: `0x${referrer.slice(2).padStart(64, "0")}`, // abi.encode(address)
    },
    instructions: {
      step1: "Include the hookData in your Uniswap v4 swap call",
      step2: "The hook will decode the referrer from hookData",
      step3: "Rewards are minted to the referrer automatically",
    },
    timestamp: Date.now(),
  });
});
