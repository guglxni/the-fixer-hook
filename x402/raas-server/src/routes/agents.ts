import { Hono } from "hono";
import { type Address, formatUnits } from "viem";
import { getRegistryContract, platformName, tierName } from "../chain.js";

/**
 * Agent routes — x402-gated agent registration, analytics, and XMTP discovery
 *
 * Covers the full Agent Infrastructure Stack:
 *  - ERC-8004 (Identity & Trust)
 *  - x402 (Payments)
 *  - XMTP (Communication)
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

  if (platform < 0 || platform > 3) {
    return c.json({ error: "Invalid platform. Use 0=Human, 1=OpenClaw, 2=Moltbook, 3=Custom" }, 400);
  }

  // In production, the server would:
  // 1. Verify the x402 payment proof was settled ($1 USDC)
  // 2. Call registry.registerAgent(agentAddress, x402ProofHash, platform) via admin key
  // 3. Return the on-chain tx hash
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
// GET /api/v1/agents/analytics/:id — Full agent analytics dashboard ($0.01)
// Unified view: x402 identity + ERC-8004 trust + XMTP communication
// ---------------------------------------------------------------------------
agentRoutes.get("/analytics/:id", async (c) => {
  const agentAddr = c.req.param("id") as Address;
  const registry = getRegistryContract();

  const [isAgent, profile, stats, totalAgents, xmtpCount] = await Promise.all([
    registry.read.isVerifiedAgent([agentAddr]),
    registry.read.getAgentProfile([agentAddr]),
    registry.read.getReferrerStats([agentAddr]),
    registry.read.getTotalAgents(),
    registry.read.getXMTPEnabledCount(),
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
      bonusMultiplierBps: Number(bonus),
    },
    // x402 Payment Layer
    x402: {
      identity: profile.x402Identity,
      totalVolume: formatUnits(profile.x402Volume, 6) + " USDC",
    },
    // ERC-8004 Identity & Trust Layer
    erc8004: {
      agentId: profile.erc8004AgentId.toString(),
      isERC8004Registered: profile.erc8004AgentId > 0n,
      cachedReputationScore: Number(profile.cachedReputationScore),
      reputationDecimals: Number(profile.cachedReputationDecimals),
      derivedBonusBps: Number(profile.derivedBonusBps),
      lastReputationUpdate: Number(profile.lastReputationUpdate),
    },
    // XMTP Communication Layer
    xmtp: {
      enabled: profile.xmtpEnabled,
      publicKeyHash: profile.xmtpPublicKeyHash,
      endpointUri: profile.xmtpEndpointUri || null,
    },
    // Referral performance
    referralStats: {
      totalVolume: formatUnits(stats.totalVolume, 18),
      referralCount: Number(stats.referralCount),
      totalEarned: formatUnits(stats.totalEarned, 18) + " FIX",
      tier: tierName(stats.tier),
    },
    ecosystem: {
      totalRegisteredAgents: Number(totalAgents),
      xmtpEnabledAgents: Number(xmtpCount),
    },
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/v1/agents/xmtp/:addr — XMTP communication discovery ($0.005)
// Returns XMTP endpoint info for agent-to-agent messaging
// ---------------------------------------------------------------------------
agentRoutes.get("/xmtp/:addr", async (c) => {
  const agentAddr = c.req.param("addr") as Address;
  const registry = getRegistryContract();

  const [isAgent, xmtpEnabled] = await Promise.all([
    registry.read.isVerifiedAgent([agentAddr]),
    registry.read.isXMTPEnabled([agentAddr]),
  ]);

  if (!isAgent) {
    return c.json({ error: "Agent not found or not verified" }, 404);
  }

  if (!xmtpEnabled) {
    return c.json({
      agent: agentAddr,
      xmtpEnabled: false,
      message: "This agent has not enabled XMTP communication",
    });
  }

  const [keyHash, endpoint, xmtpCount] = await Promise.all([
    registry.read.getXMTPPublicKeyHash([agentAddr]),
    registry.read.getXMTPEndpoint([agentAddr]),
    registry.read.getXMTPEnabledCount(),
  ]);

  return c.json({
    agent: agentAddr,
    xmtpEnabled: true,
    publicKeyHash: keyHash,
    endpointUri: endpoint,
    instructions: {
      step1: "Use the endpointUri to open an XMTP conversation with this agent",
      step2: "Messages are end-to-end encrypted via the XMTP protocol",
      step3: "The publicKeyHash can be used to verify the agent's XMTP identity",
    },
    ecosystem: {
      totalXMTPAgents: Number(xmtpCount),
    },
    timestamp: Date.now(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/v1/agents/xmtp — List XMTP ecosystem stats ($0.001)
// ---------------------------------------------------------------------------
agentRoutes.get("/xmtp", async (c) => {
  const registry = getRegistryContract();

  const [totalAgents, xmtpCount] = await Promise.all([
    registry.read.getTotalAgents(),
    registry.read.getXMTPEnabledCount(),
  ]);

  return c.json({
    xmtpEnabledAgents: Number(xmtpCount),
    totalRegisteredAgents: Number(totalAgents),
    adoptionRate:
      Number(totalAgents) > 0
        ? `${((Number(xmtpCount) / Number(totalAgents)) * 100).toFixed(1)}%`
        : "0%",
    protocol: "XMTP",
    description: "End-to-end encrypted agent-to-agent and human-to-agent messaging",
    timestamp: Date.now(),
  });
});
