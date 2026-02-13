import { Hono } from "hono";
import { type Address, formatUnits } from "viem";
import { getRegistryContract, platformName } from "../chain.js";

/**
 * Agent routes — x402-gated agent registration and analytics
 *
 * Enhancement 2 (Agent Identity) + Enhancement 7 (MCP integration prep)
 */
export const agentRoutes = new Hono();

// ---------------------------------------------------------------------------
// POST /api/v1/agents/register — Register an AI agent ($1.00 USDC via x402)
// ---------------------------------------------------------------------------
agentRoutes.post("/register", async (c) => {
  const body = await c.req.json();
  const { agentAddress, platform, x402ProofHash } = body as {
    agentAddress: Address;
    platform: number; // 0=Human, 1=OpenClaw, 2=Moltbook, 3=Custom
    x402ProofHash: string;
  };

  if (!agentAddress || platform === undefined) {
    return c.json({ error: "Missing required fields: agentAddress, platform" }, 400);
  }

  // Validate platform enum
  if (platform < 0 || platform > 3) {
    return c.json({ error: "Invalid platform. Use 0=Human, 1=OpenClaw, 2=Moltbook, 3=Custom" }, 400);
  }

  // In production, the server would:
  // 1. Verify the x402 payment proof was settled ($1 USDC)
  // 2. Call registry.registerAgent(agentAddress, x402ProofHash, platform) via admin key
  // 3. Return the on-chain tx hash
  //
  // For now, return the intent to register:
  return c.json({
    status: "registration_intent_received",
    agent: agentAddress,
    platform: platformName(platform),
    x402ProofHash: x402ProofHash ?? "pending",
    message:
      "Agent registration will be submitted on-chain via registerAgent(). " +
      "Configure ADMIN_PRIVATE_KEY in .env for automated on-chain submission.",
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/v1/analytics/agent/:id — Agent analytics dashboard ($0.01)
// ---------------------------------------------------------------------------
agentRoutes.get("/analytics/:id", async (c) => {
  const agentAddr = c.req.param("id") as Address;

  const registry = getRegistryContract();

  const [isAgent, profile, stats, totalAgents] = await Promise.all([
    registry.read.isVerifiedAgent([agentAddr]),
    registry.read.getAgentProfile([agentAddr]),
    registry.read.getReferrerStats([agentAddr]),
    registry.read.getTotalAgents(),
  ]);

  if (!isAgent) {
    return c.json({ error: "Agent not found or not verified" }, 404);
  }

  const bonus = await registry.read.getAgentMultiplierBonus([agentAddr]);

  return c.json({
    agent: {
      address: agentAddr,
      platform: platformName(profile.platform),
      verified: profile.verified,
      registeredAt: Number(profile.registeredAt),
      x402Volume: formatUnits(profile.x402Volume, 6),
      bonusMultiplierBps: Number(bonus),
    },
    referralStats: {
      totalVolume: formatUnits(stats.totalVolume, 18),
      referralCount: Number(stats.referralCount),
      totalEarned: formatUnits(stats.totalEarned, 18),
      tier: stats.tier,
    },
    ecosystem: {
      totalRegisteredAgents: Number(totalAgents),
    },
    timestamp: Date.now(),
  });
});
