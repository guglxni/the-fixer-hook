import { createPublicClient, http, type PublicClient, getContract, type Address } from "viem";
import { base } from "viem/chains";
import { config } from "./config.js";

// ============================================================================
// ABI — Read-only ABI for FixerRegistryUpgradeable v2.6.0
// Includes: Core referrals, ERC-8004 identity, x402 payments, XMTP comms
// ============================================================================

export const REGISTRY_ABI = [
  // --- Core: Referrer Stats ---
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
  // --- Core: Pool Info ---
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
  // --- Core: Global Stats ---
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
  // --- Core: Reward Calculation ---
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
  // --- Core: Hook Auth ---
  {
    name: "isAuthorizedHook",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "hook", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  // --- ERC-8004 + x402: Agent Identity ---
  {
    name: "getTotalAgents",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "count", type: "uint64" }],
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
          // v2.3 core fields
          { name: "wallet", type: "address" },
          { name: "x402Identity", type: "bytes32" },
          { name: "registeredAt", type: "uint64" },
          { name: "platform", type: "uint8" },
          { name: "x402Volume", type: "uint128" },
          { name: "verified", type: "bool" },
          { name: "bonusMultiplierBps", type: "uint16" },
          // v2.4 ERC-8004 fields
          { name: "erc8004AgentId", type: "uint256" },
          { name: "cachedReputationScore", type: "int128" },
          { name: "cachedReputationDecimals", type: "uint8" },
          { name: "derivedBonusBps", type: "uint16" },
          { name: "lastReputationUpdate", type: "uint64" },
          // v2.6 XMTP fields
          { name: "xmtpEnabled", type: "bool" },
          { name: "xmtpPublicKeyHash", type: "bytes32" },
          { name: "xmtpEndpointUri", type: "string" },
        ],
      },
    ],
  },
  {
    name: "getAgentMultiplierBonus",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "bonusBps", type: "uint16" }],
  },
  // --- XMTP Communication (v2.6) ---
  {
    name: "isXMTPEnabled",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "getXMTPPublicKeyHash",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bytes32" }],
  },
  {
    name: "getXMTPEndpoint",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "getXMTPEnabledCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },
  // --- ERC-8004: Identity NFT ---
  {
    name: "getERC8004AgentId",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  // --- Metadata ---
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

// ============================================================================
// Client
// ============================================================================

let _client: PublicClient | null = null;

/** Get or create the viem public client (read-only) */
export function getClient(): PublicClient {
  if (!_client) {
    _client = createPublicClient({
      chain: base,
      transport: http(config.chain.rpcUrl),
    });
  }
  return _client;
}

/** Get the registry contract instance */
export function getRegistryContract() {
  return getContract({
    address: config.chain.registryAddress as Address,
    abi: REGISTRY_ABI,
    client: getClient(),
  });
}

// ============================================================================
// Tier helpers
// ============================================================================

const TIER_NAMES = ["Bronze", "Silver", "Gold", "Platinum"] as const;
const PLATFORM_NAMES = ["Human", "OpenClaw", "Moltbook", "Custom"] as const;

export function tierName(tier: number): string {
  return TIER_NAMES[tier] ?? "Unknown";
}

export function platformName(platform: number): string {
  return PLATFORM_NAMES[platform] ?? "Unknown";
}

/** Check if agent has XMTP communication enabled */
export async function isAgentXMTPEnabled(agent: Address): Promise<boolean> {
  const registry = getRegistryContract();
  return registry.read.isXMTPEnabled([agent]) as Promise<boolean>;
}

/** Get agent's XMTP endpoint URI */
export async function getAgentXMTPEndpoint(agent: Address): Promise<string> {
  const registry = getRegistryContract();
  return registry.read.getXMTPEndpoint([agent]) as Promise<string>;
}

/** Get total count of XMTP-enabled agents */
export async function getXMTPEnabledCount(): Promise<bigint> {
  const registry = getRegistryContract();
  return registry.read.getXMTPEnabledCount() as Promise<bigint>;
}
