// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// OpenZeppelin Upgradeable
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// Internal
import {FixerRegistryStorage} from "./storage/FixerRegistryStorage.sol";
import {EmergencyModule} from "./modules/EmergencyModule.sol";
import {AgentTierConstants, ProtocolFeeConstants, ERC8004Constants} from "./types/AgentTypes.sol";
import {BPSMath} from "./libraries/BPSMath.sol";
import {FixerLib} from "./libraries/FixerLib.sol";

// Solady (gas-optimized math)
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

// Interfaces
import {IFixerRegistry} from "./interfaces/IFixerRegistry.sol";

// OpenZeppelin (EIP-712 for EIP-3009)
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerRegistryUpgradeable
/// @author Aaryan Guglani
/// @notice UUPS-upgradeable central registry for cross-pool referral rewards in Uniswap v4
/// @dev v2.5 — Reactive Modular Architecture:
///      - Core contract handles: Referrals, ERC20, Tiers, Emergency, Hooks, Admin
///      - Extension contract handles: ERC-8004 Agents, Delegation, Reputation, EIP-3009
///      - Library handles: Pure computation (FixerLib)
///
///      The core contract's fallback() routes unknown selectors to the extension
///      via DELEGATECALL, enabling unified ABI access through the proxy while keeping
///      each contract under the EIP-170 size limit (24,576 bytes).
///
/// Architecture:
///   ERC1967Proxy → FixerRegistryUpgradeable (Core)
///                    ├── fallback() → DELEGATECALL → FixerRegistryExtension
///                    └── FixerLib (external library, DELEGATECALL)
///   Storage: FixerRegistryStorage (ERC-7201 namespaced, shared)
///   Modules: EmergencyModule (circuit breakers, pause)
///
/// Upgrade Path:
///   v2.4.0 (monolithic) → v2.5.0 (modular: core + extension)
contract FixerRegistryUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    EmergencyModule
{
    using FixerRegistryStorage for *;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Maximum basis points (100%)
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice Contract version for upgrade tracking
    uint256 public constant VERSION = 2_006_000; // v2.6.0

    /// @notice Maximum gross reward after all multipliers (safety cap)
    /// @dev Prevents uncapped amplification from tier × reputation stacking
    uint256 public constant MAX_GROSS_REWARD = 5_000e18;

    /// @notice Maximum total supply of FIX tokens (1 billion)
    /// @dev Immutable hard cap — cannot be changed even by owner or upgrade
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    /// @notice Timelock duration for UUPS upgrades (48 hours)
    /// @dev Users have 48 hours to exit before a proposed upgrade executes
    uint256 public constant UPGRADE_TIMELOCK = 48 hours;

    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when a hook is registered with the registry
    event HookRegistered(address indexed hook, bytes32 indexed poolId);

    /// @notice Emitted when a hook is deregistered
    event HookDeregistered(address indexed hook, bytes32 indexed poolId);

    /// @notice Emitted when a cross-pool referral is recorded
    event CrossPoolReferral(
        address indexed referrer,
        address indexed swapper,
        bytes32 indexed poolId,
        uint256 volume,
        uint256 reward
    );

    /// @notice Emitted when a referrer's tier is upgraded
    event TierUpgrade(
        address indexed referrer,
        FixerRegistryStorage.ReferrerTier indexed fromTier,
        FixerRegistryStorage.ReferrerTier indexed toTier
    );

    /// @notice Emitted when tier thresholds are updated
    event TierThresholdsUpdated(
        FixerRegistryStorage.ReferrerTier indexed tier,
        FixerRegistryStorage.TierThresholds thresholds
    );

    /// @notice Emitted when reward parameters are updated
    event RewardParametersUpdated(
        uint256 minSwapAmount,
        uint256 rewardRateBps,
        uint256 maxRewardAmount,
        uint256 minRewardAmount
    );

    /// @notice Emitted when protocol fee is collected
    event ProtocolFeeCollected(uint256 fee);

    /// @notice Emitted when accumulated fees are distributed
    event FeesDistributed(uint256 treasuryShare, uint256 buybackShare, uint256 stakerShare);

    /// @notice Emitted when protocol fee BPS is updated
    event ProtocolFeeUpdated(uint64 oldFeeBps, uint64 newFeeBps);

    /// @notice Emitted when fee distribution addresses are updated
    event FeeAddressesUpdated(address indexed treasury, address indexed buyback, address stakers);

    /// @notice Emitted when an upgrade is proposed (starts timelock)
    event UpgradeProposed(address indexed newImplementation, uint256 executeAfter);

    /// @notice Emitted when a pending upgrade is cancelled
    event UpgradeCancelled(address indexed newImplementation);

    /// @notice Emitted when a timelocked upgrade is executed
    event UpgradeExecuted(address indexed newImplementation);

    /// @notice Emitted when the extension contract address is updated
    event ExtensionUpdated(address indexed oldExtension, address indexed newExtension);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error UnauthorizedHook();
    error InvalidReferrer();
    error SelfReferral();
    error InvalidParameter();
    error HookAlreadyRegistered();
    error HookNotRegistered();
    error FeeExceedsMax();
    error NoFeesToDistribute();
    error FeeAddressNotSet();
    error MaxSupplyExceeded();
    error UpgradeTimelockNotExpired(uint256 remainingTime);
    error NoUpgradePending();
    error UpgradeAlreadyPending();
    error UpgradeNotAuthorizedViaProposeExecute();

    /// @notice Extension contract not set
    error ExtensionNotSet();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /// @notice Restricts function to authorized hooks only
    modifier onlyAuthorizedHook() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.authorizedHooks[msg.sender]) revert UnauthorizedHook();
        _;
    }

    // ========================================================================
    // INITIALIZER (replaces constructor)
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the registry (called once via proxy)
    /// @param owner_ Address of the contract owner
    /// @param securityCouncil_ Address of the security multisig
    /// @param governance_ Address of DAO governance (can be address(0) initially)
    function initialize(
        address owner_,
        address securityCouncil_,
        address governance_
    ) external initializer {
        // Initialize OZ modules
        __Ownable_init(owner_);
        __ERC20_init("Fixer Token", "FIX");
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __EIP712_init("Fixer Token", "1");

        // Initialize emergency module
        __EmergencyModule_init(securityCouncil_, governance_);

        // Initialize ERC-7201 storage with default parameters
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        // Reward parameters (matching v1 defaults)
        s.minSwapAmount = 100e18;           // ~$100 equivalent
        s.rewardRateBps = 10;               // 0.1% reward rate
        s.maxRewardAmount = 1000e18;        // Maximum 1000 FIX per swap
        s.minRewardAmount = 1e18;           // Minimum 1 FIX when threshold met

        // Protocol fee (FINALIZED: 5% start, 10% max)
        s.protocolFeeBps = ProtocolFeeConstants.DEFAULT_FEE_BPS;
        s.maxProtocolFeeBps = ProtocolFeeConstants.MAX_FEE_BPS;

        // Initialize tier thresholds (matching v1)
        _initializeTiers(s);
    }

    /// @notice Re-initializer for upgrading from v2.2.1 to v2.2.2
    /// @dev Call via upgradeToAndCall for state migrations
    function reinitialize() external reinitializer(2) {
        // Reserved for v2.2.2 migrations
    }

    /// @notice Re-initializer for upgrading from v2.2.x to v2.3.0 (x402 enhancements)
    /// @dev Initializes EIP-712 domain separator for transferWithAuthorization
    function reinitializeV3() external reinitializer(3) {
        __EIP712_init("Fixer Token", "1");
    }

    /// @notice Re-initializer for upgrading from v2.3.x to v2.4.0 (ERC-8004 Trustless Agents)
    /// @dev Sets ERC-8004 registry addresses and default reputation cache TTL.
    /// @param identity_ ERC-8004 Identity Registry address
    /// @param reputation_ ERC-8004 Reputation Registry address
    /// @param validation_ ERC-8004 Validation Registry address
    function reinitializeV4(
        address identity_,
        address reputation_,
        address validation_
    ) external reinitializer(4) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        s.identityRegistry = identity_;
        s.reputationRegistry = reputation_;
        s.validationRegistry = validation_;
        s.reputationCacheTTL = ERC8004Constants.DEFAULT_CACHE_TTL;
    }

    /// @notice Re-initializer for v2.6.0 (XMTP Agent Infrastructure Stack)
    /// @dev No new storage initialization needed — XMTP fields default to 0/false.
    ///      This reinitializer serves as a version checkpoint for the upgrade.
    function reinitializeV5() external reinitializer(5) {
        // All new XMTP storage fields in AgentProfile default to zero.
        // xmtpEnabledCount in MainStorage defaults to 0.
        // No explicit initialization required.
    }

    // ========================================================================
    // CORE: REFERRAL PROCESSING
    // ========================================================================

    /// @notice Records a referral from an authorized hook
    /// @param referrer The referrer address
    /// @param swapper The address that performed the swap
    /// @param volume The swap volume
    /// @param poolId The pool identifier
    /// @return reward The reward amount minted to the referrer
    function recordReferral(
        address referrer,
        address swapper,
        uint256 volume,
        bytes32 poolId
    )
        external
        onlyAuthorizedHook
        whenNotPausedReferrals
        whenNotPausedRewards
        nonReentrant
        returns (uint256 reward)
    {
        // Validation
        if (referrer == address(0)) revert InvalidReferrer();
        if (referrer == swapper) revert SelfReferral();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        // Check minimum volume threshold
        if (volume < s.minSwapAmount) {
            return 0;
        }

        // Calculate reward with tier multiplier and protocol fee
        reward = _computeNetReward(s, referrer, volume);

        // Update all stats
        _updateStats(s, referrer, volume, poolId, reward);

        // Check for tier upgrade
        _checkTierUpgrade(s, referrer);

        // Mint reward tokens to referrer + circuit breaker check
        _checkCircuitBreaker(reward);
        _mint(referrer, reward);

        emit CrossPoolReferral(referrer, swapper, poolId, volume, reward);

        return reward;
    }

    /// @notice Computes net reward after tier multiplier, reputation bonus, and protocol fee
    /// @dev Agent bonus is derived exclusively from ERC-8004 reputation scores.
    ///      If cache is stale (> reputationCacheTTL), degrades to BONUS_LOW (500 BPS grace).
    ///      Critical: Zero external calls on hot path — all reads from cached storage.
    function _computeNetReward(
        FixerRegistryStorage.MainStorage storage s,
        address referrer,
        uint256 volume
    ) internal returns (uint256 netReward) {
        uint256 baseReward = _calculateReward(s, volume);

        // Apply referrer tier multiplier
        uint64 multiplier = s.tierThresholds[s.referrerStats[referrer].tier].multiplierBps;
        uint256 grossReward = BPSMath.applyMultiplier(baseReward, multiplier);

        // Apply ERC-8004 reputation-derived bonus (if agent)
        FixerRegistryStorage.AgentProfile storage agent = s.agentProfiles[referrer];
        if (agent.wallet != address(0) && agent.erc8004AgentId != 0) {
            uint16 effectiveBonus;

            if (
                s.reputationCacheTTL > 0 &&
                agent.lastReputationUpdate > 0 &&
                block.timestamp - agent.lastReputationUpdate > s.reputationCacheTTL
            ) {
                // Cache is stale — degrade to grace bonus (500 BPS)
                effectiveBonus = ERC8004Constants.BONUS_LOW;
            } else {
                effectiveBonus = agent.derivedBonusBps;
            }

            if (effectiveBonus > 0) {
                uint256 agentBonus = BPSMath.applyBPS(grossReward, effectiveBonus);
                grossReward += agentBonus;
            }
        }

        // FIX: F-10 — Cap gross reward to prevent uncapped tier × reputation amplification
        if (grossReward > MAX_GROSS_REWARD) {
            grossReward = MAX_GROSS_REWARD;
        }

        // Apply protocol fee
        (netReward,) = _applyProtocolFee(s, grossReward);
    }

    /// @notice Updates referrer, pool, and global stats
    /// @dev Removed unchecked blocks — uint128 overflow is practically unreachable
    ///      but safe arithmetic prevents silent stat corruption per v4-hooks audit
    function _updateStats(
        FixerRegistryStorage.MainStorage storage s,
        address referrer,
        uint256 volume,
        bytes32 poolId,
        uint256 reward
    ) internal {
        if (volume > type(uint128).max) revert InvalidParameter();
        if (reward > type(uint128).max) revert InvalidParameter();

        // Update referrer stats
        FixerRegistryStorage.ReferrerStats storage stats = s.referrerStats[referrer];
        stats.totalVolume += uint128(volume);
        stats.referralCount += 1;
        stats.lastUpdated = uint64(block.timestamp);
        stats.totalEarned += uint128(reward);

        // Update per-pool volume
        s.referrerPoolVolume[referrer][poolId] += volume;

        // Update pool info
        FixerRegistryStorage.PoolInfo storage pool = s.poolInfos[poolId];
        pool.totalReferrals += 1;
        pool.totalVolume += uint128(volume);

        // Update global counters
        s.totalReferrals += 1;
        s.totalVolume += uint128(volume);
    }

    /// @notice Checks and applies tier upgrade if eligible
    function _checkTierUpgrade(
        FixerRegistryStorage.MainStorage storage s,
        address referrer
    ) internal {
        FixerRegistryStorage.ReferrerStats storage stats = s.referrerStats[referrer];
        FixerRegistryStorage.ReferrerTier currentTier = stats.tier;
        FixerRegistryStorage.ReferrerTier newTier = _calculateTier(s, stats.totalVolume, stats.referralCount);

        if (newTier > currentTier) {
            stats.tier = newTier;
            emit TierUpgrade(referrer, currentTier, newTier);
        }
    }

    // ========================================================================
    // PROTOCOL FEE SYSTEM
    // ========================================================================

    /// @notice Distribute accumulated protocol fees
    /// @dev FINALIZED: 50% treasury / 30% buyback / 20% stakers
    ///      FIX: F-02 — Added whenNotPausedRewards + circuit breaker check
    ///      FIX: F-11 — Added onlyOwner access control
    function distributeFees() external onlyOwner nonReentrant whenNotPausedRewards {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        uint256 fees = s.accumulatedFees;
        if (fees == 0) revert NoFeesToDistribute();
        // FIX: N-02 — Require all three fee addresses to prevent silent loss of shares
        if (s.treasury == address(0) || s.buybackContract == address(0) || s.stakerRewards == address(0)) {
            revert FeeAddressNotSet();
        }

        // Clear accumulated fees before distribution (CEI)
        s.accumulatedFees = 0;

        uint256 treasuryShare = BPSMath.applyBPS(fees, ProtocolFeeConstants.TREASURY_SHARE);
        uint256 buybackShare = BPSMath.applyBPS(fees, ProtocolFeeConstants.BUYBACK_SHARE);
        uint256 stakerShare = fees - treasuryShare - buybackShare; // Remainder to avoid rounding dust

        // FIX: F-02 — Check circuit breaker before minting fee tokens
        uint256 totalMint = treasuryShare + buybackShare + stakerShare;
        _checkCircuitBreaker(totalMint);

        // Mint fee tokens to destinations
        if (treasuryShare > 0 && s.treasury != address(0)) {
            _mint(s.treasury, treasuryShare);
        }
        if (buybackShare > 0 && s.buybackContract != address(0)) {
            _mint(s.buybackContract, buybackShare);
        }
        if (stakerShare > 0 && s.stakerRewards != address(0)) {
            _mint(s.stakerRewards, stakerShare);
        }

        emit FeesDistributed(treasuryShare, buybackShare, stakerShare);
    }

    // ========================================================================
    // REWARD CALCULATION (INTERNAL)
    // ========================================================================

    /// @notice Calculates the base reward for a given volume
    function _calculateReward(
        FixerRegistryStorage.MainStorage storage s,
        uint256 volume
    ) internal view returns (uint256) {
        uint256 reward = BPSMath.applyBPS(volume, s.rewardRateBps);

        if (reward < s.minRewardAmount) {
            return s.minRewardAmount;
        }
        if (reward > s.maxRewardAmount) {
            return s.maxRewardAmount;
        }

        return reward;
    }

    /// @notice Calculates tier based on volume and referral count
    function _calculateTier(
        FixerRegistryStorage.MainStorage storage s,
        uint128 totalVol,
        uint64 refCount
    ) internal view returns (FixerRegistryStorage.ReferrerTier) {
        FixerRegistryStorage.TierThresholds memory platinum =
            s.tierThresholds[FixerRegistryStorage.ReferrerTier.Platinum];
        if (totalVol >= platinum.minVolume && refCount >= platinum.minReferrals) {
            return FixerRegistryStorage.ReferrerTier.Platinum;
        }

        FixerRegistryStorage.TierThresholds memory gold =
            s.tierThresholds[FixerRegistryStorage.ReferrerTier.Gold];
        if (totalVol >= gold.minVolume && refCount >= gold.minReferrals) {
            return FixerRegistryStorage.ReferrerTier.Gold;
        }

        FixerRegistryStorage.TierThresholds memory silver =
            s.tierThresholds[FixerRegistryStorage.ReferrerTier.Silver];
        if (totalVol >= silver.minVolume && refCount >= silver.minReferrals) {
            return FixerRegistryStorage.ReferrerTier.Silver;
        }

        return FixerRegistryStorage.ReferrerTier.Bronze;
    }

    /// @notice Apply protocol fee and accumulate
    function _applyProtocolFee(
        FixerRegistryStorage.MainStorage storage s,
        uint256 grossReward
    ) internal returns (uint256 netReward, uint256 protocolFee) {
        if (s.protocolFeeBps == 0) {
            return (grossReward, 0);
        }

        protocolFee = BPSMath.applyBPS(grossReward, s.protocolFeeBps);
        netReward = grossReward - protocolFee;

        // Safe accumulation — revert if fees would overflow uint128
        if (protocolFee > type(uint128).max - s.accumulatedFees) revert InvalidParameter();
        s.accumulatedFees += uint128(protocolFee);

        emit ProtocolFeeCollected(protocolFee);
    }

    /// @notice Initialize default tier thresholds matching v1
    function _initializeTiers(FixerRegistryStorage.MainStorage storage s) internal {
        // Bronze: Default tier
        s.tierThresholds[FixerRegistryStorage.ReferrerTier.Bronze] = FixerRegistryStorage.TierThresholds({
            minVolume: 0,
            minReferrals: 0,
            multiplierBps: 10000 // 1.0x
        });

        // Silver: 10k volume, 10 referrals
        s.tierThresholds[FixerRegistryStorage.ReferrerTier.Silver] = FixerRegistryStorage.TierThresholds({
            minVolume: 10_000e18,
            minReferrals: 10,
            multiplierBps: 12500 // 1.25x
        });

        // Gold: 100k volume, 50 referrals
        s.tierThresholds[FixerRegistryStorage.ReferrerTier.Gold] = FixerRegistryStorage.TierThresholds({
            minVolume: 100_000e18,
            minReferrals: 50,
            multiplierBps: 15000 // 1.5x
        });

        // Platinum: 1M volume, 200 referrals
        s.tierThresholds[FixerRegistryStorage.ReferrerTier.Platinum] = FixerRegistryStorage.TierThresholds({
            minVolume: 1_000_000e18,
            minReferrals: 200,
            multiplierBps: 20000 // 2.0x
        });
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Gets a referrer's stats
    function getReferrerStats(address referrer)
        external
        view
        returns (FixerRegistryStorage.ReferrerStats memory)
    {
        return FixerRegistryStorage.getStorage().referrerStats[referrer];
    }

    /// @notice Gets a referrer's volume in a specific pool
    function getPoolVolume(address referrer, bytes32 poolId) external view returns (uint256) {
        return FixerRegistryStorage.getStorage().referrerPoolVolume[referrer][poolId];
    }

    /// @notice Gets pool information
    function getPoolInfo(bytes32 poolId)
        external
        view
        returns (FixerRegistryStorage.PoolInfo memory)
    {
        return FixerRegistryStorage.getStorage().poolInfos[poolId];
    }

    /// @notice Gets the tier thresholds for a specific tier
    function getTierThresholds(FixerRegistryStorage.ReferrerTier tier)
        external
        view
        returns (FixerRegistryStorage.TierThresholds memory)
    {
        return FixerRegistryStorage.getStorage().tierThresholds[tier];
    }

    /// @notice Checks if a hook is authorized
    function isAuthorizedHook(address hook) external view returns (bool) {
        return FixerRegistryStorage.getStorage().authorizedHooks[hook];
    }

    /// @notice Gets progress toward the next tier
    function getProgressToNextTier(address referrer)
        external
        view
        returns (
            FixerRegistryStorage.ReferrerTier currentTier,
            FixerRegistryStorage.ReferrerTier nextTier,
            uint256 volumeProgress,
            uint256 referralProgress
        )
    {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.ReferrerStats memory stats = s.referrerStats[referrer];
        currentTier = stats.tier;

        // Already at Platinum
        if (currentTier == FixerRegistryStorage.ReferrerTier.Platinum) {
            return (currentTier, currentTier, 10000, 10000);
        }

        // Determine next tier
        if (currentTier == FixerRegistryStorage.ReferrerTier.Bronze) {
            nextTier = FixerRegistryStorage.ReferrerTier.Silver;
        } else if (currentTier == FixerRegistryStorage.ReferrerTier.Silver) {
            nextTier = FixerRegistryStorage.ReferrerTier.Gold;
        } else {
            nextTier = FixerRegistryStorage.ReferrerTier.Platinum;
        }

        FixerRegistryStorage.TierThresholds memory nextThresholds = s.tierThresholds[nextTier];

        // Volume progress
        if (nextThresholds.minVolume == 0) {
            volumeProgress = 10000;
        } else {
            volumeProgress = FixedPointMathLib.mulDiv(
                uint256(stats.totalVolume), 10000, nextThresholds.minVolume
            );
            if (volumeProgress > 10000) volumeProgress = 10000;
        }

        // Referral progress
        if (nextThresholds.minReferrals == 0) {
            referralProgress = 10000;
        } else {
            referralProgress = FixedPointMathLib.mulDiv(
                uint256(stats.referralCount), 10000, uint256(nextThresholds.minReferrals)
            );
            if (referralProgress > 10000) referralProgress = 10000;
        }
    }

    /// @notice Public reward calculator (no tier)
    function calculateReward(uint256 volume) external view returns (uint256) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (volume < s.minSwapAmount) return 0;
        return _calculateReward(s, volume);
    }

    /// @notice Public reward calculator with tier multiplier (gross, before protocol fee)
    function calculateRewardWithTier(uint256 volume, address referrer) external view returns (uint256) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (volume < s.minSwapAmount) return 0;

        uint256 baseReward = _calculateReward(s, volume);
        FixerRegistryStorage.ReferrerTier tier = s.referrerStats[referrer].tier;
        uint64 multiplier = s.tierThresholds[tier].multiplierBps;

        return BPSMath.applyMultiplier(baseReward, multiplier);
    }

    /// @notice Public reward calculator returning the net reward (after tier, reputation bonus, and protocol fee)
    /// @dev FIX: N-01 — Mirrors _computeNetReward logic in read-only mode so frontends
    ///      can show users the actual reward they will receive, not the inflated gross amount.
    /// @param volume The swap volume
    /// @param referrer The referrer address (used for tier + ERC-8004 bonus lookup)
    /// @return netReward The reward the referrer would actually receive after all deductions
    function calculateNetReward(uint256 volume, address referrer) external view returns (uint256 netReward) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (volume < s.minSwapAmount) return 0;

        uint256 baseReward = _calculateReward(s, volume);

        // Apply referrer tier multiplier
        uint64 multiplier = s.tierThresholds[s.referrerStats[referrer].tier].multiplierBps;
        uint256 grossReward = BPSMath.applyMultiplier(baseReward, multiplier);

        // Apply ERC-8004 reputation-derived bonus (read-only)
        FixerRegistryStorage.AgentProfile storage agent = s.agentProfiles[referrer];
        if (agent.wallet != address(0) && agent.erc8004AgentId != 0) {
            uint16 effectiveBonus;

            if (
                s.reputationCacheTTL > 0 &&
                agent.lastReputationUpdate > 0 &&
                block.timestamp - agent.lastReputationUpdate > s.reputationCacheTTL
            ) {
                effectiveBonus = ERC8004Constants.BONUS_LOW;
            } else {
                effectiveBonus = agent.derivedBonusBps;
            }

            if (effectiveBonus > 0) {
                grossReward += BPSMath.applyBPS(grossReward, effectiveBonus);
            }
        }

        // Cap gross reward
        if (grossReward > MAX_GROSS_REWARD) {
            grossReward = MAX_GROSS_REWARD;
        }

        // Apply protocol fee (view-only — no accumulation)
        if (s.protocolFeeBps > 0) {
            uint256 fee = BPSMath.applyBPS(grossReward, s.protocolFeeBps);
            return grossReward - fee;
        }
        return grossReward;
    }

    /// @notice Get accumulated protocol fees
    function getAccumulatedFees() external view returns (uint256) {
        return FixerRegistryStorage.getStorage().accumulatedFees;
    }

    /// @notice Get protocol fee configuration
    function getProtocolFeeConfig() external view returns (uint64 feeBps, uint64 maxFeeBps) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        return (s.protocolFeeBps, s.maxProtocolFeeBps);
    }

    /// @notice Get global protocol stats
    function getGlobalStats()
        external
        view
        returns (uint64 hookCount, uint64 totalReferrals_, uint128 totalVolume_)
    {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        return (s.hookCount, s.totalReferrals, s.totalVolume);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /// @notice Registers a hook for a specific pool
    function registerHook(address hook, bytes32 poolId) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.authorizedHooks[hook]) revert HookAlreadyRegistered();

        s.authorizedHooks[hook] = true;
        s.poolInfos[poolId].hookAddress = hook;
        s.poolInfos[poolId].active = true;

        // FIX: F-19 — Use checked arithmetic (consistent with deregisterHook)
        s.hookCount += 1;

        emit HookRegistered(hook, poolId);
    }

    /// @notice Deregisters a hook
    function deregisterHook(address hook, bytes32 poolId) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.authorizedHooks[hook]) revert HookNotRegistered();

        s.authorizedHooks[hook] = false;
        s.poolInfos[poolId].active = false;
        s.hookCount -= 1;

        emit HookDeregistered(hook, poolId);
    }

    /// @notice Sets the reward parameters
    /// @dev Validates all downcasts to prevent silent truncation
    function setRewardParameters(
        uint256 _minSwapAmount,
        uint256 _rewardRateBps,
        uint256 _maxRewardAmount,
        uint256 _minRewardAmount
    ) external onlyOwner {
        if (_rewardRateBps > BPS_DENOMINATOR) revert InvalidParameter();
        if (_minRewardAmount > _maxRewardAmount) revert InvalidParameter();
        if (_minSwapAmount > type(uint128).max) revert InvalidParameter();
        if (_maxRewardAmount > type(uint128).max) revert InvalidParameter();
        if (_minRewardAmount > type(uint128).max) revert InvalidParameter();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        s.minSwapAmount = uint128(_minSwapAmount);
        s.rewardRateBps = uint64(_rewardRateBps);
        s.maxRewardAmount = uint128(_maxRewardAmount);
        s.minRewardAmount = uint128(_minRewardAmount);

        emit RewardParametersUpdated(_minSwapAmount, _rewardRateBps, _maxRewardAmount, _minRewardAmount);
    }

    /// @notice Sets the thresholds for a specific tier
    function setTierThresholds(
        FixerRegistryStorage.ReferrerTier tier,
        FixerRegistryStorage.TierThresholds calldata thresholds
    ) external onlyOwner {
        if (thresholds.multiplierBps > 100_000) revert InvalidParameter(); // Max 10x

        FixerRegistryStorage.getStorage().tierThresholds[tier] = thresholds;

        emit TierThresholdsUpdated(tier, thresholds);
    }

    /// @notice Sets the protocol fee (basis points)
    /// @dev Cannot exceed maxProtocolFeeBps hard cap
    function setProtocolFee(uint64 newFeeBps) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (newFeeBps > s.maxProtocolFeeBps) revert FeeExceedsMax();

        uint64 oldFeeBps = s.protocolFeeBps;
        s.protocolFeeBps = newFeeBps;

        emit ProtocolFeeUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice Sets the fee distribution addresses
    function setFeeAddresses(
        address treasury_,
        address buybackContract_,
        address stakerRewards_
    ) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        s.treasury = treasury_;
        s.buybackContract = buybackContract_;
        s.stakerRewards = stakerRewards_;

        emit FeeAddressesUpdated(treasury_, buybackContract_, stakerRewards_);
    }

    // ========================================================================
    // UUPS UPGRADE TIMELOCK
    // ========================================================================

    /// @notice Propose an upgrade to a new implementation (starts 48h timelock)
    /// @param newImplementation The address of the new implementation contract
    function proposeUpgrade(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert InvalidParameter();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.pendingUpgrade.active) revert UpgradeAlreadyPending();

        s.pendingUpgrade = FixerRegistryStorage.UpgradeProposal({
            newImplementation: newImplementation,
            proposedAt: uint64(block.timestamp),
            active: true
        });

        emit UpgradeProposed(newImplementation, block.timestamp + UPGRADE_TIMELOCK);
    }

    /// @notice Cancel a pending upgrade proposal
    function cancelUpgrade() external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.pendingUpgrade.active) revert NoUpgradePending();

        address cancelled = s.pendingUpgrade.newImplementation;
        delete s.pendingUpgrade;

        emit UpgradeCancelled(cancelled);
    }

    /// @notice Execute a proposed upgrade after the timelock has expired
    /// @dev Calls UUPSUpgradeable.upgradeToAndCall which triggers _authorizeUpgrade.
    ///      FIX: F-01 — _authorizeUpgrade now validates and cleans up the proposal,
    ///      so we don't delete it here (it must be present for validation).
    function executeUpgrade() external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.pendingUpgrade.active) revert NoUpgradePending();

        uint256 elapsed = block.timestamp - s.pendingUpgrade.proposedAt;
        if (elapsed < UPGRADE_TIMELOCK) {
            revert UpgradeTimelockNotExpired(UPGRADE_TIMELOCK - elapsed);
        }

        address newImpl = s.pendingUpgrade.newImplementation;

        emit UpgradeExecuted(newImpl);

        // This calls _authorizeUpgrade internally, which validates + clears the proposal
        upgradeToAndCall(newImpl, "");
    }

    /// @notice Get the pending upgrade proposal details
    function getPendingUpgrade()
        external
        view
        returns (address newImplementation, uint256 proposedAt, bool active, uint256 executeAfter)
    {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.UpgradeProposal memory p = s.pendingUpgrade;
        return (
            p.newImplementation,
            p.proposedAt,
            p.active,
            p.active ? p.proposedAt + UPGRADE_TIMELOCK : 0
        );
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Enforces the full propose → timelock → execute flow.
    ///      Direct calls to upgradeToAndCall() are blocked — must go through
    ///      proposeUpgrade() → wait 48h → executeUpgrade().
    ///      FIX: F-01 — Previously only checked onlyOwner, allowing timelock bypass.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.pendingUpgrade.active) revert UpgradeNotAuthorizedViaProposeExecute();
        if (s.pendingUpgrade.newImplementation != newImplementation) revert InvalidParameter();
        uint256 elapsed = block.timestamp - s.pendingUpgrade.proposedAt;
        if (elapsed < UPGRADE_TIMELOCK) {
            revert UpgradeTimelockNotExpired(UPGRADE_TIMELOCK - elapsed);
        }
        // Clear proposal after validation — prevents replay
        delete s.pendingUpgrade;
    }

    // ========================================================================
    // EXTENSION: REACTIVE MODULAR ARCHITECTURE
    // ========================================================================

    /// @notice Set the extension contract address for agent + EIP-3009 functions
    /// @dev The extension is called via DELEGATECALL from fallback().
    ///      It shares the same ERC-7201 storage layout and OZ inheritance chain.
    ///      Must be set before agent registration or EIP-3009 transfers work.
    /// @param extension_ Address of the deployed FixerRegistryExtension contract
    function setExtension(address extension_) external onlyOwner {
        if (extension_ == address(0)) revert InvalidParameter();
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        address old = s.extension;
        s.extension = extension_;
        emit ExtensionUpdated(old, extension_);
    }

    /// @notice Get the current extension contract address
    function getExtension() external view returns (address) {
        return FixerRegistryStorage.getStorage().extension;
    }

    /// @notice Fallback routes unknown selectors to the extension via DELEGATECALL
    /// @dev This enables the Agent Infrastructure Stack (ERC-8004, EIP-3009, delegation)
    ///      to live in a separate contract while presenting a unified ABI through the proxy.
    ///      DELEGATECALL preserves msg.sender, msg.value, and storage context.
    fallback() external payable {
        address ext = FixerRegistryStorage.getStorage().extension;
        if (ext == address(0)) revert ExtensionNotSet();

        assembly {
            // Copy calldata
            calldatacopy(0, 0, calldatasize())
            // Delegatecall to extension
            let result := delegatecall(gas(), ext, 0, calldatasize(), 0, 0)
            // Copy returndata
            returndatacopy(0, 0, returndatasize())
            // Forward result
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Accept ETH (required for fallback to be payable)
    receive() external payable {}

    // ========================================================================
    // ERC20 OVERRIDES
    // ========================================================================

    /// @notice Enforces MAX_SUPPLY cap on all mints
    /// @dev Overrides ERC20Upgradeable._update which is called by _mint and _transfer
    ///      Only checks supply cap on mint operations (from == address(0))
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) && totalSupply() + value > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }
        super._update(from, to, value);
    }

    /// @notice Returns the number of decimals (18)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
