import { Hono } from "hono";
import { type Address, formatUnits } from "viem";
import { getRegistryContract, tierName, platformName } from "../chain.js";

/**
 * Pool routes — x402-gated analytics for FixerHook pools
 *
 * Enhancement 1 (RaaS API) + Enhancement 5 (Analytics)
 */
export const poolRoutes = new Hono();

// ---------------------------------------------------------------------------
// GET /api/v1/pools — List active pools ($0.001)
// ---------------------------------------------------------------------------
poolRoutes.get("/", async (c) => {
  const registry = getRegistryContract();

  const [hookCount, totalReferrals, totalVolume] = await registry.read.getGlobalStats();

  return c.json({
    totalPools: Number(hookCount),
    totalReferrals: Number(totalReferrals),
    totalVolume: formatUnits(totalVolume, 18),
    // NOTE: In production, iterate known poolIds from an off-chain index.
    // The on-chain registry does not expose a pool enumeration.
    // This response provides global stats; individual pool data requires poolId.
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/v1/pools/:id/stats — Detailed pool stats ($0.005)
// ---------------------------------------------------------------------------
poolRoutes.get("/:id/stats", async (c) => {
  const poolId = c.req.param("id") as `0x${string}`;

  const registry = getRegistryContract();
  const info = await registry.read.getPoolInfo([poolId]);

  if (!info.active) {
    return c.json({ error: "Pool not found or inactive" }, 404);
  }

  return c.json({
    poolId,
    hookAddress: info.hookAddress,
    active: info.active,
    totalReferrals: Number(info.totalReferrals),
    totalVolume: formatUnits(info.totalVolume, 18),
    timestamp: Date.now(),
  });
});
