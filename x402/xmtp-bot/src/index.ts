import "dotenv/config";

import {
  createPublicClient,
  http,
  formatUnits,
  type Address,
  type PublicClient,
  getContract,
} from "viem";
import { baseSepolia } from "viem/chains";

// ============================================================================
// CONFIG
// ============================================================================

const config = {
  /** Private key for the XMTP bot's wallet (ECDSA hex, 0x-prefixed) */
  walletKey: process.env.XMTP_BOT_KEY!,
  /** RPC URL for reading on-chain state */
  rpcUrl: process.env.RPC_URL ?? "https://sepolia.base.org",
  /** FixerRegistry proxy address */
  registryAddress: process.env.REGISTRY_ADDRESS! as Address,
  /** XMTP environment: "production" | "dev" */
  xmtpEnv: (process.env.XMTP_ENV ?? "dev") as "production" | "dev",
};

// ============================================================================
// ABI — Minimal read ABI for XMTP-relevant functions
// ============================================================================

const REGISTRY_ABI = [
  {
    name: "isVerifiedAgent",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "isXMTPEnabled",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "getXMTPEndpoint",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ name: "endpointUri", type: "string" }],
  },
  {
    name: "getXMTPEnabledCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "count", type: "uint64" }],
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
          { name: "erc8004AgentId", type: "uint256" },
          { name: "cachedReputationScore", type: "int128" },
          { name: "cachedReputationDecimals", type: "uint8" },
          { name: "derivedBonusBps", type: "uint16" },
          { name: "lastReputationUpdate", type: "uint64" },
          { name: "xmtpEnabled", type: "bool" },
          { name: "xmtpPublicKeyHash", type: "bytes32" },
          { name: "xmtpEndpointUri", type: "string" },
        ],
      },
    ],
  },
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
    name: "getTotalAgents",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "count", type: "uint64" }],
  },
] as const;

// ============================================================================
// CHAIN CLIENT
// ============================================================================

const client: PublicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(config.rpcUrl),
});

const registry = getContract({
  address: config.registryAddress,
  abi: REGISTRY_ABI,
  client,
});

// ============================================================================
// TIER & PLATFORM HELPERS
// ============================================================================

const TIER_NAMES = ["Bronze", "Silver", "Gold", "Platinum"] as const;
const PLATFORM_NAMES = ["Human", "OpenClaw", "Moltbook", "Custom"] as const;

function tierName(tier: number): string {
  return TIER_NAMES[tier] ?? "Unknown";
}

function platformName(platform: number): string {
  return PLATFORM_NAMES[platform] ?? "Unknown";
}

// ============================================================================
// COMMAND HANDLERS
// ============================================================================

type CommandHandler = (
  senderAddress: string,
  args: string
) => Promise<string>;

/**
 * /stats — Get ecosystem stats
 */
const handleStats: CommandHandler = async () => {
  const [totalAgents, xmtpCount] = await Promise.all([
    registry.read.getTotalAgents(),
    registry.read.getXMTPEnabledCount(),
  ]);

  return [
    "📊 **Fixer Protocol Stats**",
    `• Registered agents: ${totalAgents}`,
    `• XMTP-enabled agents: ${xmtpCount}`,
  ].join("\n");
};

/**
 * /profile <address> — Lookup agent profile
 */
const handleProfile: CommandHandler = async (_sender, args) => {
  const addr = args.trim() as Address;
  if (!addr || !addr.startsWith("0x") || addr.length !== 42) {
    return "Usage: /profile <0x address>";
  }

  const [isAgent, isXmtp, profile, stats] = await Promise.all([
    registry.read.isVerifiedAgent([addr]),
    registry.read.isXMTPEnabled([addr]),
    registry.read.getAgentProfile([addr]),
    registry.read.getReferrerStats([addr]),
  ]);

  if (!isAgent) {
    return `❌ Address ${addr} is not a verified agent.`;
  }

  return [
    `🤖 **Agent Profile: ${addr.slice(0, 8)}...${addr.slice(-4)}**`,
    `• Platform: ${platformName(profile.platform)}`,
    `• Tier: ${tierName(stats.tier)}`,
    `• Referrals: ${stats.referralCount}`,
    `• Volume: ${formatUnits(stats.totalVolume, 18)} units`,
    `• FIX earned: ${formatUnits(stats.totalEarned, 18)}`,
    `• Reputation bonus: ${Number(profile.derivedBonusBps) / 100}%`,
    `• XMTP: ${isXmtp ? "✅ Enabled" : "❌ Disabled"}`,
    isXmtp ? `• XMTP endpoint: ${profile.xmtpEndpointUri}` : "",
  ]
    .filter(Boolean)
    .join("\n");
};

/**
 * /estimate <volume> <referrer> — Estimate referral reward
 */
const handleEstimate: CommandHandler = async (_sender, args) => {
  const parts = args.trim().split(/\s+/);
  if (parts.length < 2) {
    return "Usage: /estimate <volume> <referrer address>";
  }

  const volume = BigInt(Math.floor(parseFloat(parts[0]) * 1e18));
  const referrer = parts[1] as Address;

  try {
    const reward = await registry.read.calculateRewardWithTier([volume, referrer]);
    return [
      `💰 **Reward Estimate**`,
      `• Volume: ${parts[0]} units`,
      `• Referrer: ${referrer.slice(0, 8)}...`,
      `• Estimated FIX reward: ${formatUnits(reward, 18)}`,
    ].join("\n");
  } catch {
    return "❌ Could not estimate reward. Check that the referrer exists.";
  }
};

/**
 * /xmtp <address> — Check XMTP status of an agent
 */
const handleXmtp: CommandHandler = async (_sender, args) => {
  const addr = args.trim() as Address;
  if (!addr || !addr.startsWith("0x") || addr.length !== 42) {
    return "Usage: /xmtp <0x address>";
  }

  const [isEnabled, endpoint] = await Promise.all([
    registry.read.isXMTPEnabled([addr]),
    registry.read.getXMTPEndpoint([addr]),
  ]);

  if (!isEnabled) {
    return `❌ Agent ${addr.slice(0, 8)}... does not have XMTP enabled.`;
  }

  return [
    `📨 **XMTP Status: ${addr.slice(0, 8)}...**`,
    `• XMTP: ✅ Enabled`,
    `• Endpoint: ${endpoint || "(no URI set)"}`,
    `• You can message this agent directly via XMTP!`,
  ].join("\n");
};

/**
 * /help — List available commands
 */
const handleHelp: CommandHandler = async () => {
  return [
    "🔧 **Fixer Referral Bot — Commands**",
    "",
    "• `/stats` — Ecosystem statistics",
    "• `/profile <address>` — Agent profile lookup",
    "• `/estimate <volume> <referrer>` — Estimate referral reward",
    "• `/xmtp <address>` — Check agent's XMTP status",
    "• `/help` — This message",
    "",
    "Powered by Fixer Protocol v2.6 — Agent Infrastructure Stack",
    "XMTP + x402 + ERC-8004",
  ].join("\n");
};

// Command router
const COMMANDS: Record<string, CommandHandler> = {
  "/stats": handleStats,
  "/profile": handleProfile,
  "/estimate": handleEstimate,
  "/xmtp": handleXmtp,
  "/help": handleHelp,
};

// ============================================================================
// MESSAGE PROCESSOR
// ============================================================================

/**
 * Process an incoming XMTP message and return a response.
 * This function is framework-agnostic — it can be called from any XMTP client.
 */
export async function processMessage(
  senderAddress: string,
  content: string
): Promise<string> {
  const trimmed = content.trim();

  // Parse command
  const spaceIdx = trimmed.indexOf(" ");
  const command = spaceIdx === -1 ? trimmed.toLowerCase() : trimmed.slice(0, spaceIdx).toLowerCase();
  const args = spaceIdx === -1 ? "" : trimmed.slice(spaceIdx + 1);

  const handler = COMMANDS[command];
  if (handler) {
    try {
      return await handler(senderAddress, args);
    } catch (error) {
      console.error(`Error handling command ${command}:`, error);
      return "❌ An error occurred processing your request. Please try again.";
    }
  }

  // Default response for unrecognized messages
  return [
    `👋 Hello! I'm the Fixer Referral Bot.`,
    ``,
    `Type /help to see available commands.`,
    ``,
    `I can look up agent profiles, estimate rewards, and check XMTP status.`,
  ].join("\n");
}

// ============================================================================
// XMTP CLIENT BOOTSTRAP
// ============================================================================

/**
 * Start the XMTP bot.
 *
 * NOTE: This uses the @xmtp/node-sdk pattern. Install it with:
 *   npm install @xmtp/node-sdk
 *
 * The bot listens for all incoming conversations and messages,
 * then routes them through processMessage().
 */
async function startBot() {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║          Fixer XMTP Referral Bot v1.0.0                 ║
╠══════════════════════════════════════════════════════════╣
║  Registry: ${(config.registryAddress ?? "not set").slice(0, 44).padEnd(44)}║
║  RPC:      ${config.rpcUrl.slice(0, 44).padEnd(44)}║
║  XMTP Env: ${config.xmtpEnv.padEnd(44)}║
╚══════════════════════════════════════════════════════════╝
`);

  // Validate config
  if (!config.walletKey) {
    console.error("ERROR: XMTP_BOT_KEY environment variable is not set.");
    console.error("Set it to a hex-encoded ECDSA private key (0x...).");
    process.exit(1);
  }

  if (!config.registryAddress) {
    console.error("ERROR: REGISTRY_ADDRESS environment variable is not set.");
    process.exit(1);
  }

  try {
    // Dynamic import to allow the package to be optional
    const { Client } = await import("@xmtp/node-sdk");

    // Create XMTP client from wallet key
    // The exact API depends on the @xmtp/node-sdk version
    const client = await Client.create(
      { getAddress: async () => config.walletKey } as any,
      { env: config.xmtpEnv }
    );

    console.log(`✅ XMTP client created. Bot address: ${client.address}`);
    console.log("Listening for messages...\n");

    // Stream all conversations
    const stream = await client.conversations.stream();

    for await (const conversation of stream) {
      // Stream messages in each conversation
      const messageStream = await conversation.streamMessages();

      for await (const message of messageStream) {
        // Skip our own messages
        if (message.senderAddress === client.address) continue;

        console.log(`[${new Date().toISOString()}] ${message.senderAddress}: ${message.content}`);

        const response = await processMessage(
          message.senderAddress,
          String(message.content)
        );

        await conversation.send(response);
        console.log(`[${new Date().toISOString()}] BOT -> ${message.senderAddress}: ${response.slice(0, 80)}...`);
      }
    }
  } catch (error) {
    // If @xmtp/node-sdk is not installed, run in CLI mode
    if ((error as any)?.code === "ERR_MODULE_NOT_FOUND") {
      console.log("@xmtp/node-sdk not installed. Running in CLI test mode.");
      console.log("Install with: npm install @xmtp/node-sdk\n");
      await runCliMode();
    } else {
      throw error;
    }
  }
}

/**
 * CLI test mode — allows testing message processing without XMTP SDK.
 */
async function runCliMode() {
  const readline = await import("readline");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log("=== CLI Test Mode ===");
  console.log("Type XMTP commands (e.g., /help, /stats, /profile 0x...)");
  console.log("Press Ctrl+C to exit.\n");

  const prompt = () => {
    rl.question("> ", async (input) => {
      if (!input.trim()) {
        prompt();
        return;
      }

      const response = await processMessage("0xTestUser", input);
      console.log(`\n${response}\n`);
      prompt();
    });
  };

  prompt();
}

// Start the bot
startBot().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
