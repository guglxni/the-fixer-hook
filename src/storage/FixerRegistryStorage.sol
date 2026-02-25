// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title FixerRegistryStorage
/// @author Aaryan Guglani
/// @notice ERC-7201 namespaced storage for FixerRegistryUpgradeable
/// @dev Uses diamond storage pattern with deterministic slot computation
///      to ensure upgrade-safe storage layout across proxy implementations.
///
/// Storage Namespace: fixer.registry.storage.main
/// ERC-7201 Reference: https://eips.ethereum.org/EIPS/eip-7201
///
/// Layout Notes:
/// - Slot Group 1: Reward parameters (packed into 1 slot)
/// - Slot Group 2: Reward bounds (packed into 1 slot)
/// - Slot Group 3: Protocol fee params (packed into 1 slot, FINALIZED: 5% start, 10% max)
/// - Slot Group 4: Global counters (packed into 1 slot)
/// - Mappings: Hook auth, pool info, referrer stats, agent registry, teams
/// - Gap: 40 reserved slots for future extensions (reduced from 45 by ERC-8004 v2.4)
library FixerRegistryStorage {
    // ========================================================================
    // ERC-7201 STORAGE LOCATION
    // ========================================================================

    /// @custom:storage-location erc7201:fixer.registry.storage.main
    /// @dev keccak256(abi.encode(uint256(keccak256("fixer.registry.storage.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT =
        keccak256(abi.encode(uint256(keccak256("fixer.registry.storage.main")) - 1)) & ~bytes32(uint256(0xff));

    // ========================================================================
    // ENUMS
    // ========================================================================

    /// @notice Referrer tier levels (preserved from v1)
    enum ReferrerTier {
        Bronze,   // 1.0x multiplier
        Silver,   // 1.25x multiplier
        Gold,     // 1.5x multiplier
        Platinum  // 2.0x multiplier
    }

    /// @notice Agent verification tier based on stake amount
    /// @dev FINALIZED: Tiered staking from 100 FIX to 10,000 FIX
    enum AgentTier {
        Unverified,   // 0 FIX - no rewards, testing only
        Starter,      // 100 FIX - basic rewards, 1 chain
        Professional, // 1,000 FIX - 1.25x multiplier, multi-chain
        Enterprise,   // 10,000 FIX - 1.5x multiplier, featured
        Audited       // 10,000 FIX + audit - 2.0x multiplier
    }

    // ========================================================================
    // STRUCTS
    // ========================================================================

    /// @notice Tier thresholds and multiplier configuration (preserved from v1)
    struct TierThresholds {
        uint128 minVolume;     // Minimum cumulative volume to qualify
        uint64 minReferrals;   // Minimum referral count to qualify
        uint64 multiplierBps;  // Reward multiplier in bps (10000 = 1.0x)
    }

    /// @notice Per-referrer statistics (preserved from v1)
    struct ReferrerStats {
        uint128 totalVolume;   // Cumulative volume across all pools
        uint64 referralCount;  // Total referral count
        uint64 lastUpdated;    // Timestamp of last activity
        uint128 totalEarned;   // Total FIX tokens earned
        ReferrerTier tier;     // Current tier level
    }

    /// @notice Per-pool information (preserved from v1)
    struct PoolInfo {
        address hookAddress;   // Address of the hook for this pool
        bool active;           // Whether the pool is active
        uint64 totalReferrals; // Total referrals in this pool
        uint128 totalVolume;   // Total volume in this pool
    }

    /// @notice Agent tier threshold configuration
    /// @dev FINALIZED: stake, multiplier, slashing, chain access
    struct AgentTierThresholds {
        uint256 minStake;             // Minimum FIX stake required
        uint16 rewardMultiplierBps;   // Reward multiplier (10000 = 1.0x)
        uint16 slashingRateBps;       // Slashing rate on violation
        uint8 maxChains;              // Number of chains accessible
        bool marketplaceFeatured;     // Featured in marketplace
    }

    /// @notice Agent information stored on-chain
    struct AgentInfo {
        bool isRegistered;
        AgentTier tier;
        address operator;             // Who controls the agent
        uint256 stakedAmount;         // FIX tokens staked
        uint256 registeredAt;
        uint256 lastActivityAt;
        uint64 totalVolume;           // Volume generated
        uint32 referralCount;         // Successful referrals
        bytes32 ipfsMetadata;         // Agent description hash
    }

    /// @notice Team information for referrer teams
    struct TeamInfo {
        address leader;
        uint8 maxMembers;             // Based on leader tier
        uint8 memberCount;
        uint16 bonusPoolBps;          // Team bonus pool percentage
        uint16 leaderShareBps;        // Leader's share of bonus
        bool active;
    }

    /// @notice Emergency/circuit breaker state
    struct EmergencyState {
        bool pausedReferrals;         // Pause referral processing
        bool pausedAgents;            // Pause agent operations
        bool pausedRewards;           // Pause reward minting
        uint64 pausedReferralsAt;     // When referrals were paused
        uint64 pausedAgentsAt;        // When agents were paused
        uint64 pausedRewardsAt;       // When rewards were paused
        uint256 circuitBreakerThreshold; // Max FIX per hour
        uint256 mintedThisHour;
        uint64 hourStartedAt;
        address securityCouncil;      // Multisig for emergencies
        address governance;           // DAO governance address
        uint256 mintedToday;          // Daily aggregate mint tracking
        uint64 dayStartedAt;          // When the current day period started
    }

    /// @notice Agent type classification for x402-registered agents
    /// @dev Maps to platforms: OpenClaw, Moltbook, custom
    enum AgentPlatform {
        Human,      // 0 — Regular human referrer
        OpenClaw,   // 1 — Agent running on OpenClaw
        Moltbook,   // 2 — Agent from Moltbook network
        Custom      // 3 — Any other agent framework
    }

    /// @notice Agent profile stored on-chain (ERC-8004 verified via Identity NFT ownership)
    /// @dev Created via registerAgent(uint256 agentId, AgentPlatform platform) — permissionless.
    ///      v2.4: Extended with ERC-8004 fields. Appending to mapping-based struct is storage-safe —
    ///      existing entries get zero-default values for new fields.
    ///      v2.6: Extended with XMTP fields for Agent Infrastructure Stack completeness.
    struct AgentProfile {
        // --- Existing v2.3 fields (DO NOT reorder) ---
        address wallet;                  // The agent's Ethereum address
        bytes32 x402Identity;            // Hash of x402 client identity (payment proof)
        uint64 registeredAt;             // Timestamp when agent registered
        AgentPlatform platform;          // Which platform the agent runs on
        uint128 x402Volume;              // Total x402 payments made (trust signal)
        bool verified;                   // Whether identity was verified
        uint16 bonusMultiplierBps;       // Agent-specific bonus multiplier (0 = no bonus)
        // --- ERC-8004 Extension Fields (v2.4, appended safely) ---
        uint256 erc8004AgentId;          // ERC-8004 NFT token ID (0 = not ERC-8004 registered)
        int128 cachedReputationScore;    // Cached reputation value from ERC-8004 Reputation Registry
        uint8 cachedReputationDecimals;  // Decimals for interpreting cachedReputationScore
        uint16 derivedBonusBps;          // Bonus BPS auto-computed from reputation score
        uint64 lastReputationUpdate;     // Timestamp of last reputation cache refresh
        // --- XMTP Communication Fields (v2.6, appended safely) ---
        bool xmtpEnabled;                // Whether this agent is reachable via XMTP
        bytes32 xmtpPublicKeyHash;       // keccak256 of the agent's XMTP installation key
        string xmtpEndpointUri;          // Full XMTP endpoint URI (e.g., "xmtp://0x.../inbox")
    }

    /// @notice Pending UUPS upgrade proposal (timelock)
    struct UpgradeProposal {
        address newImplementation;    // Proposed implementation address
        uint64 proposedAt;            // When the proposal was created
        bool active;                  // Whether there's an active proposal
    }

    // ========================================================================
    // MAIN STORAGE STRUCT
    // ========================================================================

    /// @notice Main storage layout for FixerRegistryUpgradeable
    /// @dev All state variables are stored in this struct via ERC-7201.
    ///      Order matters — do NOT reorder fields after deployment.
    struct MainStorage {
        // ═══════════════════════════════════════════════════════════════
        // SLOT GROUP 1: Reward Parameters (1 slot packed)
        // ═══════════════════════════════════════════════════════════════
        uint128 minSwapAmount;
        uint64 rewardRateBps;
        uint64 __reserved1;

        // ═══════════════════════════════════════════════════════════════
        // SLOT GROUP 2: Reward Bounds (1 slot packed)
        // ═══════════════════════════════════════════════════════════════
        uint128 maxRewardAmount;
        uint128 minRewardAmount;

        // ═══════════════════════════════════════════════════════════════
        // SLOT GROUP 3: Protocol Fee Parameters (FINALIZED: 5% start)
        // ═══════════════════════════════════════════════════════════════
        uint64 protocolFeeBps;       // 500 = 5%, max 1000 = 10%
        uint64 maxProtocolFeeBps;    // 1000 = 10% hard cap
        uint128 accumulatedFees;     // Unclaimed protocol fees

        // ═══════════════════════════════════════════════════════════════
        // SLOT GROUP 4: Global Counters (1 slot packed)
        // ═══════════════════════════════════════════════════════════════
        uint64 hookCount;
        uint64 totalReferrals;
        uint128 totalVolume;

        // ═══════════════════════════════════════════════════════════════
        // MAPPINGS (v1 — preserved)
        // ═══════════════════════════════════════════════════════════════
        mapping(address => bool) authorizedHooks;
        mapping(bytes32 => PoolInfo) poolInfos;
        mapping(address => ReferrerStats) referrerStats;
        mapping(address => mapping(bytes32 => uint256)) referrerPoolVolume;
        mapping(ReferrerTier => TierThresholds) tierThresholds;

        // ═══════════════════════════════════════════════════════════════
        // MAPPINGS (v2 — new)
        // ═══════════════════════════════════════════════════════════════
        mapping(address => AgentInfo) agentRegistry;
        mapping(AgentTier => AgentTierThresholds) agentTierThresholds;
        mapping(address => TeamInfo) referrerTeams;
        mapping(address => address) teamMembership; // member => leader

        // ═══════════════════════════════════════════════════════════════
        // EMERGENCY STATE
        // ═══════════════════════════════════════════════════════════════
        EmergencyState emergency;

        // ═══════════════════════════════════════════════════════════════
        // FEE DISTRIBUTION ADDRESSES
        // ═══════════════════════════════════════════════════════════════
        address treasury;
        address buybackContract;
        address stakerRewards;

        // ═══════════════════════════════════════════════════════════════
        // UPGRADE TIMELOCK
        // ═══════════════════════════════════════════════════════════════
        UpgradeProposal pendingUpgrade;

        // ═══════════════════════════════════════════════════════════════
        // x402 AGENT PROFILES (v2.3 — x402 enhancement)
        // ═══════════════════════════════════════════════════════════════
        mapping(address => AgentProfile) agentProfiles;
        uint64 totalAgents;
        mapping(uint8 => uint64) agentPlatformCount; // AgentPlatform => count

        // ═══════════════════════════════════════════════════════════════
        // REFERRAL DELEGATION (v2.3 — marketplace)
        // ═══════════════════════════════════════════════════════════════
        /// @dev delegator => delegate => allowed
        ///      Allows an agent to use another referrer's tier for referrals
        mapping(address => mapping(address => bool)) referralDelegations;

        // ═══════════════════════════════════════════════════════════════
        // EIP-3009 AUTHORIZATION STATE (v2.3 — FIX as x402 currency)
        // ═══════════════════════════════════════════════════════════════
        /// @dev Authorization nonce tracking: keccak256(from, nonce) => used
        mapping(bytes32 => bool) authorizationStates;

        // ═══════════════════════════════════════════════════════════════
        // ERC-8004 REGISTRY CONFIGURATION (v2.4 — Trustless Agents)
        // ═══════════════════════════════════════════════════════════════
        /// @notice ERC-8004 Identity Registry address (verifies NFT ownership + agentWallet)
        address identityRegistry;
        /// @notice ERC-8004 Reputation Registry address (reads reputation, writes feedback)
        address reputationRegistry;
        /// @notice ERC-8004 Validation Registry address (checks third-party scores)
        address validationRegistry;
        /// @notice Reverse mapping: ERC-8004 agent NFT ID => wallet address
        mapping(uint256 => address) agentIdToWallet;
        /// @notice Count of ERC-8004 registered agents + reputation cache TTL (packed)
        uint64 erc8004AgentCount;
        uint64 reputationCacheTTL;           // Default: 3600 (1 hour)

        // ═══════════════════════════════════════════════════════════════
        // EXTENSION CONTRACT (v2.5 — Reactive Modular Architecture)
        // ═══════════════════════════════════════════════════════════════
        /// @notice Extension contract for agent + EIP-3009 functions (delegatecall target)
        /// @dev Set via setExtension(). Core contract's fallback() routes unknown selectors
        ///      to this address via DELEGATECALL. Same ERC-7201 storage layout ensures
        ///      unified state access across core and extension.
        address extension;

        // ═══════════════════════════════════════════════════════════════
        // XMTP COMMUNICATION STATE (v2.6 — Agent Infrastructure Stack)
        // ═══════════════════════════════════════════════════════════════
        /// @notice Count of agents with XMTP communication enabled
        uint64 xmtpEnabledCount;

        // ═══════════════════════════════════════════════════════════════
        // GAP: Reserve slots for future upgrades (38 slots)
        // Reduced from 39 — consumed 1 slot for XMTP state
        // ═══════════════════════════════════════════════════════════════
        uint256[38] __gap;
    }

    // ========================================================================
    // STORAGE ACCESS
    // ========================================================================

    /// @notice Returns a reference to the main storage struct
    /// @dev Uses assembly to load from the ERC-7201 deterministic slot
    function getStorage() internal pure returns (MainStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
