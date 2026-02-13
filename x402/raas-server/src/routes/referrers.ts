import { Hono } from "hono";
import { type Address, formatUnits } from "viem";
import { getRegistryContract, tierName } from "../chain.js";

/**
 * Referrer routes — x402-gated referrer discovery and profiles
 *
 * Enhancement 1 (RaaS API) — Referrer Discovery
 */
export const referrerRoutes = new Hono();

// ---------------------------------------------------------------------------
// GET /api/v1/referrers/top — Top referrers by tier ($0.01)
// ---------------------------------------------------------------------------
referrerRoutes.get("/top", async (c) => {
  // NOTE: In production, this would query an off-chain index/subgraph
  // that listens to CrossPoolReferral events and ranks referrers.
  // The on-chain registry doesn't provide enumeration of all referrers.
  //
  // For now, return a schema placeholder that the indexer would populate.
  return c.json({
    description: "Top referrers ranked by tier and volume",
    schema: {
      referrers: [
        {
          address: "0x...",
          tier: "Platinum",
          totalVolume: "1000000.0",
          referralCount: 250,
          totalEarned: "5000.0",
          isAgent: false,
        },
      ],
    },
    note: "Connect a subgraph indexer to populate live data from CrossPoolReferral events",
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/v1/referrers/:addr — Full referrer profile ($0.005)
// ---------------------------------------------------------------------------
referrerRoutes.get("/:addr", async (c) => {
  const addr = c.req.param("addr") as Address;

  const registry = getRegistryContract();

  const [stats, progress, isAgent] = await Promise.all([
    registry.read.getReferrerStats([addr]),
    registry.read.getProgressToNextTier([addr]),
    registry.read.isVerifiedAgent([addr]),
  ]);

  // If the referrer has a zero referral count, they may not exist
  if (stats.referralCount === 0n) {
    return c.json({ error: "Referrer not found or has no activity" }, 404);
  }

  let agentProfile = null;
  if (isAgent) {
    const profile = await registry.read.getAgentProfile([addr]);
    const bonus = await registry.read.getAgentMultiplierBonus([addr]);
    agentProfile = {
      platform: profile.platform,
      x402Volume: formatUnits(profile.x402Volume, 6),
      verified: profile.verified,
      bonusMultiplierBps: Number(bonus),
      registeredAt: Number(profile.registeredAt),
    };
  }

  return c.json({
    address: addr,
    tier: tierName(stats.tier),
    totalVolume: formatUnits(stats.totalVolume, 18),
    referralCount: Number(stats.referralCount),
    totalEarned: formatUnits(stats.totalEarned, 18),
    lastUpdated: Number(stats.lastUpdated),
    progress: {
      currentTier: tierName(progress.currentTier),
      nextTier: tierName(progress.nextTier),
      volumeProgress: `${Number(progress.volumeProgress) / 100}%`,
      referralProgress: `${Number(progress.referralProgress) / 100}%`,
    },
    isAgent,
    agentProfile,
    timestamp: Date.now(),
  });
});
