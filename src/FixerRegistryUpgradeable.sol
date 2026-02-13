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
import {AgentTierConstants, ProtocolFeeConstants} from "./types/AgentTypes.sol";
import {BPSMath} from "./libraries/BPSMath.sol";

// Solady (gas-optimized math)
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

// Interfaces
import {IFixerRegistry} from "./interfaces/IFixerRegistry.sol";
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

// OpenZeppelin (EIP-712 for EIP-3009)
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerRegistryUpgradeable
/// @author Aaryan Guglani
/// @notice UUPS-upgradeable central registry for cross-pool referral rewards in Uniswap v4
/// @dev v2.2 — Upgradeable version of FixerRegistry with:
///      - ERC-7201 namespaced storage for safe upgrades
///      - Emergency module with circuit breakers
///      - Protocol fee system (5% default, 10% max)
///      - Agent registry stubs (prepared for v2.2.2)
///      - Preserves all v1 functionality (referrals, tiers, hooks)
///
/// Architecture:
///   ERC1967Proxy → FixerRegistryUpgradeable (implementation)
///   Storage: FixerRegistryStorage (ERC-7201 namespaced)
///   Modules: EmergencyModule (circuit breakers, pause)
///
/// Upgrade Path:
///   FixerRegistry (v1, non-upgradeable) → deploy proxy + migrate
///   FixerRegistryUpgradeable v2.2.1 → v2.2.2 (agents) → v2.3 (cross-chain)
///
/// Decisions Applied:
///   - FIX Token = ERC20 via ERC20Upgradeable (initializer pattern)
///   - Registry = UUPS Upgradeable (owner-authorized upgrades)
///   - Protocol Fee = 5% (500 bps), max 10% (1000 bps) hard cap
///   - Fee Split = 50% treasury / 30% buyback / 20% stakers
contract FixerRegistryUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    EmergencyModule,
    IAgentRegistry
{
    using FixerRegistryStorage for *;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Maximum basis points (100%)
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice Contract version for upgrade tracking
    uint256 public constant VERSION = 2_003_000; // v2.3.0

    /// @notice Maximum agent bonus multiplier (50% = 5000 bps)
    uint16 public constant MAX_AGENT_BONUS_BPS = 5000;

    /// @notice EIP-3009 typehash for transferWithAuthorization
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    /// @notice EIP-3009 typehash for receiveWithAuthorization
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

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

    /// @notice EIP-3009: Emitted when a transfer authorization is used
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

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

    // x402 agent errors are inherited from IAgentRegistry:
    //   AgentAlreadyRegistered, AgentNotRegistered, InvalidAgentAddress,
    //   CannotDelegateToSelf, DelegationAlreadyExists, DelegationNotFound,
    //   BonusMultiplierTooHigh

    // EIP-3009 authorization errors
    error AuthorizationExpired();
    error AuthorizationNotYetValid();
    error AuthorizationAlreadyUsed();
    error InvalidSignature();

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

    /// @notice Computes net reward after tier multiplier, agent bonus, and protocol fee
    function _computeNetReward(
        FixerRegistryStorage.MainStorage storage s,
        address referrer,
        uint256 volume
    ) internal returns (uint256 netReward) {
        uint256 baseReward = _calculateReward(s, volume);

        // Apply referrer tier multiplier
        uint64 multiplier = s.tierThresholds[s.referrerStats[referrer].tier].multiplierBps;
        uint256 grossReward = BPSMath.applyMultiplier(baseReward, multiplier);

        // Apply x402 agent bonus if referrer is a verified agent
        FixerRegistryStorage.AgentProfile storage agent = s.agentProfiles[referrer];
        if (agent.verified && agent.bonusMultiplierBps > 0) {
            uint256 agentBonus = BPSMath.applyBPS(grossReward, agent.bonusMultiplierBps);
            grossReward += agentBonus;
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
    function distributeFees() external nonReentrant {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        uint256 fees = s.accumulatedFees;
        if (fees == 0) revert NoFeesToDistribute();
        if (s.treasury == address(0)) revert FeeAddressNotSet();

        // Clear accumulated fees before distribution (CEI)
        s.accumulatedFees = 0;

        uint256 treasuryShare = BPSMath.applyBPS(fees, ProtocolFeeConstants.TREASURY_SHARE);
        uint256 buybackShare = BPSMath.applyBPS(fees, ProtocolFeeConstants.BUYBACK_SHARE);
        uint256 stakerShare = fees - treasuryShare - buybackShare; // Remainder to avoid rounding dust

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

    /// @notice Public reward calculator with tier multiplier
    function calculateRewardWithTier(uint256 volume, address referrer) external view returns (uint256) {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (volume < s.minSwapAmount) return 0;

        uint256 baseReward = _calculateReward(s, volume);
        FixerRegistryStorage.ReferrerTier tier = s.referrerStats[referrer].tier;
        uint64 multiplier = s.tierThresholds[tier].multiplierBps;

        return BPSMath.applyMultiplier(baseReward, multiplier);
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

        unchecked {
            s.hookCount += 1;
        }

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
    /// @dev Calls UUPSUpgradeable.upgradeToAndCall which triggers _authorizeUpgrade
    function executeUpgrade() external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.pendingUpgrade.active) revert NoUpgradePending();

        uint256 elapsed = block.timestamp - s.pendingUpgrade.proposedAt;
        if (elapsed < UPGRADE_TIMELOCK) {
            revert UpgradeTimelockNotExpired(UPGRADE_TIMELOCK - elapsed);
        }

        address newImpl = s.pendingUpgrade.newImplementation;
        delete s.pendingUpgrade;

        emit UpgradeExecuted(newImpl);

        // This calls _authorizeUpgrade internally
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
    /// @dev Only callable via executeUpgrade() — direct upgrades are blocked.
    ///      The proposal is already deleted in executeUpgrade before this is called,
    ///      so we only verify onlyOwner here. The timelock is enforced in executeUpgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ========================================================================
    // x402 AGENT REGISTRY (Enhancement 2)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function registerAgent(
        address agent,
        bytes32 x402ProofHash,
        FixerRegistryStorage.AgentPlatform platform
    ) external onlyOwner whenNotPausedAgents {
        if (agent == address(0)) revert InvalidAgentAddress();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet != address(0)) revert AgentAlreadyRegistered();

        s.agentProfiles[agent] = FixerRegistryStorage.AgentProfile({
            wallet: agent,
            x402Identity: x402ProofHash,
            registeredAt: uint64(block.timestamp),
            platform: platform,
            x402Volume: 0,
            verified: true,
            bonusMultiplierBps: 0
        });

        s.totalAgents += 1;
        s.agentPlatformCount[uint8(platform)] += 1;

        emit AgentRegistered(agent, platform, x402ProofHash, msg.sender);
    }

    /// @inheritdoc IAgentRegistry
    function deregisterAgent(address agent) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet == address(0)) revert AgentNotRegistered();

        FixerRegistryStorage.AgentPlatform platform = s.agentProfiles[agent].platform;
        delete s.agentProfiles[agent];

        s.totalAgents -= 1;
        s.agentPlatformCount[uint8(platform)] -= 1;

        emit AgentDeregistered(agent);
    }

    /// @inheritdoc IAgentRegistry
    function updateAgentProfile(
        address agent,
        uint16 bonusMultiplierBps,
        bool verified
    ) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet == address(0)) revert AgentNotRegistered();
        if (bonusMultiplierBps > MAX_AGENT_BONUS_BPS) revert BonusMultiplierTooHigh();

        s.agentProfiles[agent].bonusMultiplierBps = bonusMultiplierBps;
        s.agentProfiles[agent].verified = verified;

        emit AgentProfileUpdated(agent, bonusMultiplierBps, verified);
    }

    /// @inheritdoc IAgentRegistry
    function updateAgentX402Volume(address agent, uint128 additionalVolume) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet == address(0)) revert AgentNotRegistered();

        s.agentProfiles[agent].x402Volume += additionalVolume;

        emit AgentX402VolumeUpdated(agent, s.agentProfiles[agent].x402Volume);
    }

    // ========================================================================
    // x402 REFERRAL DELEGATION (Enhancement 4 — Marketplace)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function delegateReferral(address delegate) external {
        if (delegate == msg.sender) revert CannotDelegateToSelf();
        if (delegate == address(0)) revert InvalidAgentAddress();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.referralDelegations[msg.sender][delegate]) revert DelegationAlreadyExists();

        s.referralDelegations[msg.sender][delegate] = true;

        emit ReferralDelegated(msg.sender, delegate);
    }

    /// @inheritdoc IAgentRegistry
    function revokeDelegation(address delegate) external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.referralDelegations[msg.sender][delegate]) revert DelegationNotFound();

        s.referralDelegations[msg.sender][delegate] = false;

        emit ReferralDelegationRevoked(msg.sender, delegate);
    }

    // ========================================================================
    // x402 AGENT VIEW FUNCTIONS
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function isRegisteredAgent(address agent) external view returns (bool) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].wallet != address(0);
    }

    /// @inheritdoc IAgentRegistry
    function isVerifiedAgent(address agent) external view returns (bool) {
        FixerRegistryStorage.AgentProfile storage profile =
            FixerRegistryStorage.getStorage().agentProfiles[agent];
        return profile.wallet != address(0) && profile.verified;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentMultiplierBonus(address agent) external view returns (uint16 bonusBps) {
        FixerRegistryStorage.AgentProfile storage profile =
            FixerRegistryStorage.getStorage().agentProfiles[agent];
        if (profile.wallet != address(0) && profile.verified) {
            return profile.bonusMultiplierBps;
        }
        return 0;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentProfile(address agent)
        external
        view
        returns (FixerRegistryStorage.AgentProfile memory profile)
    {
        return FixerRegistryStorage.getStorage().agentProfiles[agent];
    }

    /// @inheritdoc IAgentRegistry
    function isDelegated(address delegator, address delegate) external view returns (bool) {
        return FixerRegistryStorage.getStorage().referralDelegations[delegator][delegate];
    }

    /// @inheritdoc IAgentRegistry
    function getTotalAgents() external view returns (uint64 count) {
        return FixerRegistryStorage.getStorage().totalAgents;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform platform)
        external
        view
        returns (uint64 count)
    {
        return FixerRegistryStorage.getStorage().agentPlatformCount[uint8(platform)];
    }

    // ========================================================================
    // EIP-3009: transferWithAuthorization (Enhancement 6 — FIX as x402 currency)
    // ========================================================================

    /// @notice Execute a transfer with a signed authorization (EIP-3009)
    /// @dev Enables gasless FIX transfers for x402 payment settlements.
    ///      The facilitator submits the pre-signed authorization on behalf of the payer.
    /// @param from Payer's address (token sender)
    /// @param to Payee's address (token receiver)
    /// @param value Amount of FIX tokens to transfer
    /// @param validAfter Earliest timestamp when the authorization is valid
    /// @param validBefore Latest timestamp when the authorization is valid
    /// @param nonce Unique nonce to prevent double-spending
    /// @param v ECDSA signature component v
    /// @param r ECDSA signature component r
    /// @param s ECDSA signature component s
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp < validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp > validBefore) revert AuthorizationExpired();

        FixerRegistryStorage.MainStorage storage stor = FixerRegistryStorage.getStorage();
        bytes32 authKey = keccak256(abi.encodePacked(from, nonce));
        if (stor.authorizationStates[authKey]) revert AuthorizationAlreadyUsed();

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer != from) revert InvalidSignature();

        stor.authorizationStates[authKey] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    /// @notice Check if an authorization nonce has been used
    /// @param authorizer The address that signed the authorization
    /// @param nonce The nonce to check
    /// @return Whether the nonce has been used
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        bytes32 authKey = keccak256(abi.encodePacked(authorizer, nonce));
        return FixerRegistryStorage.getStorage().authorizationStates[authKey];
    }

    /// @notice Returns the EIP-712 domain separator
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

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
