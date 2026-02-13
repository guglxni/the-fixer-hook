#!/usr/bin/env node

/**
 * FixerHook MCP Server
 *
 * Exposes FixerHook referral system tools via the Model Context Protocol (MCP).
 * AI agents (Claude, ChatGPT, etc.) can discover and call these tools to:
 *
 * 1. Query active pools and reward parameters
 * 2. Check referrer profiles and tier status
 * 3. Calculate estimated rewards for a given volume
 * 4. Get agent analytics dashboards
 * 5. Submit referral intents (pre-encoded hookData)
 *
 * Enhancement 7 from X402_ENHANCEMENT_ANALYSIS.md
 *
 * Usage:
 *   npx @fixerhook/mcp-server
 *
 * MCP Client Configuration (claude_desktop_config.json):
 *   {
 *     "mcpServers": {
 *       "fixerhook": {
 *         "command": "npx",
 *         "args": ["@fixerhook/mcp-server"],
 *         "env": {
 *           "RPC_URL": "https://mainnet.base.org",
 *           "REGISTRY_ADDRESS": "0x..."
 *         }
 *       }
 *     }
 *   }
 */

import "dotenv/config";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  createPublicClient,
  http,
  formatUnits,
  parseUnits,
  type Address,
} from "viem";
import { base } from "viem/chains";

// ============================================================================
// CONFIG
// ============================================================================

const RPC_URL = process.env.RPC_URL ?? "https://mainnet.base.org";
const REGISTRY_ADDRESS = process.env.REGISTRY_ADDRESS as Address;

// Minimal ABI for read-only calls
const REGISTRY_ABI = [
  {
    name: "getReferrerStats",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "referrer", type: "address" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "totalVolume", type: "uint128" },
          { name: "referralCount", type: "uint64" },
          { name: "lastUpdated", type: "uint64" },
          { name: "totalEarned", type: "uint128" },
          { name: "tier", type: "uint8" },
        ],
      },
    ],
  },
  {
    name: "getGlobalStats",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "hookCount", type: "uint64" },
      { name: "totalReferrals", type: "uint64" },
      { name: "totalVolume", type: "uint128" },
    ],
  },
  {
    name: "calculateRewardWithTier",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "volume", type: "uint256" },
      { name: "referrer", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getProgressToNextTier",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "referrer", type: "address" }],
    outputs: [
      { name: "currentTier", type: "uint8" },
      { name: "nextTier", type: "uint8" },
      { name: "volumeProgress", type: "uint256" },
      { name: "referralProgress", type: "uint256" },
    ],
  },
  {
    name: "isVerifiedAgent",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "getAgentProfile",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "wallet", type: "address" },
          { name: "x402Identity", type: "bytes32" },
          { name: "registeredAt", type: "uint64" },
          { name: "platform", type: "uint8" },
          { name: "x402Volume", type: "uint128" },
          { name: "verified", type: "bool" },
          { name: "bonusMultiplierBps", type: "uint16" },
        ],
      },
    ],
  },
  {
    name: "getTotalAgents",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "count", type: "uint64" }],
  },
  {
    name: "getPoolInfo",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "hookAddress", type: "address" },
          { name: "active", type: "bool" },
          { name: "totalReferrals", type: "uint64" },
          { name: "totalVolume", type: "uint128" },
        ],
      },
    ],
  },
  {
    name: "VERSION",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

const TIER_NAMES = ["Bronze", "Silver", "Gold", "Platinum"];
const PLATFORM_NAMES = ["Human", "OpenClaw", "Moltbook", "Custom"];

// ============================================================================
// VIEM CLIENT
// ============================================================================

const client = createPublicClient({
  chain: base,
  transport: http(RPC_URL),
});

async function readContract(functionName: string, args: unknown[] = []) {
  return client.readContract({
    address: REGISTRY_ADDRESS,
    abi: REGISTRY_ABI,
    functionName,
    args,
  } as any);
}

// ============================================================================
// MCP SERVER
// ============================================================================

const server = new McpServer({
  name: "fixerhook",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// Tool: fixer_get_pools
// ---------------------------------------------------------------------------
server.tool(
  "fixer_get_pools",
  "Get active FixerHook pools with global reward statistics. Returns total pools, referrals, volume, and FIX token supply.",
  {},
  async () => {
    const [hookCount, totalReferrals, totalVolume] = (await readContract(
      "getGlobalStats"
    )) as [bigint, bigint, bigint];
    const supply = (await readContract("totalSupply")) as bigint;
    const version = (await readContract("VERSION")) as bigint;

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              registryVersion: version.toString(),
              totalPools: Number(hookCount),
              totalReferrals: Number(totalReferrals),
              totalVolume: formatUnits(totalVolume, 18),
              fixTokenSupply: formatUnits(supply, 18),
              network: "Base (eip155:8453)",
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Tool: fixer_check_rewards
// ---------------------------------------------------------------------------
server.tool(
  "fixer_check_rewards",
  "Calculate estimated FIX token rewards for a given swap volume and referrer address. Shows tier multiplier and bonus.",
  {
    volume: z.string().describe("Swap volume in token units (e.g., '50000' for 50K)"),
    referrer: z.string().describe("Ethereum address of the referrer (0x...)"),
  },
  async ({ volume, referrer }) => {
    const volumeWei = parseUnits(volume, 18);
    const reward = (await readContract("calculateRewardWithTier", [
      volumeWei,
      referrer as Address,
    ])) as bigint;

    const stats = (await readContract("getReferrerStats", [
      referrer as Address,
    ])) as any;
    const progress = (await readContract("getProgressToNextTier", [
      referrer as Address,
    ])) as any;

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              inputVolume: volume,
              referrer,
              estimatedReward: formatUnits(reward, 18) + " FIX",
              referrerTier: TIER_NAMES[stats.tier] ?? "Unknown",
              progress: {
                nextTier: TIER_NAMES[progress.nextTier] ?? "Max",
                volumeProgress: `${Number(progress.volumeProgress) / 100}%`,
                referralProgress: `${Number(progress.referralProgress) / 100}%`,
              },
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Tool: fixer_referrer_profile
// ---------------------------------------------------------------------------
server.tool(
  "fixer_referrer_profile",
  "Get full profile of a referrer including stats, tier, earnings, and agent status.",
  {
    address: z.string().describe("Ethereum address of the referrer (0x...)"),
  },
  async ({ address }) => {
    const addr = address as Address;
    const stats = (await readContract("getReferrerStats", [addr])) as any;
    const isAgent = (await readContract("isVerifiedAgent", [addr])) as boolean;

    let agentInfo = null;
    if (isAgent) {
      const profile = (await readContract("getAgentProfile", [addr])) as any;
      agentInfo = {
        platform: PLATFORM_NAMES[profile.platform] ?? "Unknown",
        x402Volume: formatUnits(profile.x402Volume, 6) + " USDC",
        verified: profile.verified,
        bonusMultiplierBps: Number(profile.bonusMultiplierBps),
      };
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              address: addr,
              tier: TIER_NAMES[stats.tier] ?? "Unknown",
              totalVolume: formatUnits(stats.totalVolume, 18),
              referralCount: Number(stats.referralCount),
              totalEarned: formatUnits(stats.totalEarned, 18) + " FIX",
              isVerifiedAgent: isAgent,
              agentInfo,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Tool: fixer_submit_referral
// ---------------------------------------------------------------------------
server.tool(
  "fixer_submit_referral",
  "Generate the encoded hookData for a Uniswap v4 swap with a FixerHook referral. Returns the bytes to include in the swap call.",
  {
    referrer: z.string().describe("Ethereum address of the referrer (0x...)"),
  },
  async ({ referrer }) => {
    // abi.encode(address) = pad address to 32 bytes
    const encoded = `0x${referrer.slice(2).toLowerCase().padStart(64, "0")}`;

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              referrer,
              hookData: encoded,
              instructions: [
                "Include this hookData in your Uniswap v4 swap transaction",
                "The FixerHookV2 will decode the referrer address from hookData",
                "Rewards are automatically minted to the referrer by the registry",
                "Minimum swap volume must be met for rewards to apply",
              ],
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Tool: fixer_agent_dashboard
// ---------------------------------------------------------------------------
server.tool(
  "fixer_agent_dashboard",
  "Get comprehensive analytics for a verified AI agent including referral stats, earnings, and ecosystem metrics.",
  {
    agentAddress: z.string().describe("Ethereum address of the AI agent (0x...)"),
  },
  async ({ agentAddress }) => {
    const addr = agentAddress as Address;
    const isAgent = (await readContract("isVerifiedAgent", [addr])) as boolean;

    if (!isAgent) {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({
              error: "Agent not found or not verified",
              suggestion:
                "Register as an agent via the RaaS API (POST /api/v1/agents/register) with $1 USDC x402 payment",
            }),
          },
        ],
      };
    }

    const [profile, stats, totalAgents, globalStats] = (await Promise.all([
      readContract("getAgentProfile", [addr]),
      readContract("getReferrerStats", [addr]),
      readContract("getTotalAgents"),
      readContract("getGlobalStats"),
    ])) as [any, any, bigint, [bigint, bigint, bigint]];

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              agent: {
                address: addr,
                platform: PLATFORM_NAMES[profile.platform] ?? "Unknown",
                verified: profile.verified,
                registeredAt: new Date(
                  Number(profile.registeredAt) * 1000
                ).toISOString(),
                x402Volume: formatUnits(profile.x402Volume, 6) + " USDC",
              },
              performance: {
                totalVolume: formatUnits(stats.totalVolume, 18),
                referralCount: Number(stats.referralCount),
                totalEarned: formatUnits(stats.totalEarned, 18) + " FIX",
                tier: TIER_NAMES[stats.tier] ?? "Unknown",
              },
              ecosystem: {
                totalAgents: Number(totalAgents),
                totalPools: Number(globalStats[0]),
                totalProtocolVolume: formatUnits(globalStats[2], 18),
              },
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ============================================================================
// START SERVER
// ============================================================================

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("FixerHook MCP Server running on stdio");
}

main().catch(console.error);
