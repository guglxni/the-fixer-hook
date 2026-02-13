// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// Interface
import {IFixerRegistry} from "./interfaces/IFixerRegistry.sol";

// Token Standard (Solmate for gas efficiency)
import {ERC20} from "solmate/src/tokens/ERC20.sol";

// Solady for gas-optimized utilities
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerRegistry
/// @author Aaryan Guglani
/// @notice Central registry for cross-pool referral rewards in Uniswap v4
/// @dev Manages the FIX token, referrer statistics, and tier system across multiple hooks
///
/// Architecture:
/// - Single source of truth for all referrer statistics
/// - Multiple FixerHookV2 contracts delegate to this registry
/// - Unified tier progression across all pools
/// - FIX token minting controlled by authorized hooks only
///
/// v2.0 Features:
/// - Cross-pool statistics tracking
/// - Per-pool analytics (volume, referral count)
/// - Authorized hook system for security
/// - Unified tier system with multipliers
/// - Gas-optimized storage layout
contract FixerRegistry is IFixerRegistry, ERC20, Ownable {
    
    // ========================================================================
    // CONSTANTS
    // ========================================================================
    
    /// @notice Maximum basis points (100%)
    uint256 private constant BPS_DENOMINATOR = 10000;
    
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================
    
    /// @notice Authorized hooks that can record referrals
    mapping(address => bool) public authorizedHooks;
    
    /// @notice Mapping from pool ID to pool info
    mapping(bytes32 => PoolInfo) public poolInfos;
    
    /// @notice Per-referrer global statistics
    mapping(address => ReferrerStats) internal _referrerStats;
    
    /// @notice Per-referrer, per-pool volume tracking
    /// @dev referrer => poolId => volume
    mapping(address => mapping(bytes32 => uint256)) public referrerPoolVolume;
    
    /// @notice Tier thresholds and multipliers
    mapping(ReferrerTier => TierThresholds) internal _tierThresholds;
    
    /// @notice Global minimum swap amount for rewards
    uint256 public minSwapAmount;
    
    /// @notice Global reward rate in basis points
    uint256 public rewardRateBps;
    
    /// @notice Global maximum reward per swap
    uint256 public maxRewardAmount;
    
    /// @notice Global minimum reward per swap
    uint256 public minRewardAmount;
    
    /// @notice Total number of registered hooks
    uint256 public hookCount;
    
    /// @notice Total referrals processed across all pools
    uint256 public totalReferrals;
    
    /// @notice Total volume processed across all pools
    uint256 public totalVolume;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /// @notice Initializes the FixerRegistry with token and owner
    /// @param _owner Address of the contract owner
    constructor(address _owner) ERC20("Fixer Token", "FIX", 18) {
        _initializeOwner(_owner);
        
        // Initialize default reward parameters
        minSwapAmount = 100 * 1e18;        // Minimum ~$100 equivalent
        rewardRateBps = 10;                 // 0.1% reward rate
        maxRewardAmount = 1000 * 1e18;      // Maximum 1000 FIX per swap
        minRewardAmount = 1 * 1e18;         // Minimum 1 FIX when threshold met
        
        // Initialize tier thresholds
        _initializeTiers();
    }
    
    /// @notice Initializes the default tier thresholds
    function _initializeTiers() internal {
        // Bronze: Default tier, no requirements, 1.0x multiplier
        _tierThresholds[ReferrerTier.Bronze] = TierThresholds({
            minVolume: 0,
            minReferrals: 0,
            multiplierBps: 10000  // 1.0x
        });
        
        // Silver: 10k volume, 10 referrals, 1.25x multiplier
        _tierThresholds[ReferrerTier.Silver] = TierThresholds({
            minVolume: 10_000 * 1e18,
            minReferrals: 10,
            multiplierBps: 12500  // 1.25x
        });
        
        // Gold: 100k volume, 50 referrals, 1.5x multiplier
        _tierThresholds[ReferrerTier.Gold] = TierThresholds({
            minVolume: 100_000 * 1e18,
            minReferrals: 50,
            multiplierBps: 15000  // 1.5x
        });
        
        // Platinum: 1M volume, 200 referrals, 2.0x multiplier
        _tierThresholds[ReferrerTier.Platinum] = TierThresholds({
            minVolume: 1_000_000 * 1e18,
            minReferrals: 200,
            multiplierBps: 20000  // 2.0x
        });
    }
    
    // ========================================================================
    // MODIFIERS
    // ========================================================================
    
    /// @notice Restricts function to authorized hooks only
    modifier onlyAuthorizedHook() {
        if (!authorizedHooks[msg.sender]) revert UnauthorizedHook();
        _;
    }
    
    // ========================================================================
    // CORE FUNCTIONS
    // ========================================================================
    
    /// @inheritdoc IFixerRegistry
    function recordReferral(
        address referrer,
        address swapper,
        uint256 volume,
        bytes32 poolId
    ) external onlyAuthorizedHook returns (uint256 reward) {
        // Validation
        if (referrer == address(0)) revert InvalidReferrer();
        if (referrer == swapper) revert SelfReferral();
        
        // Check minimum volume threshold
        if (volume < minSwapAmount) {
            return 0;
        }
        
        // Calculate base reward
        uint256 baseReward = _calculateReward(volume);
        
        // Get referrer stats and apply tier multiplier
        ReferrerStats storage stats = _referrerStats[referrer];
        TierThresholds memory tierConfig = _tierThresholds[stats.tier];
        
        reward = FixedPointMathLib.mulDiv(baseReward, tierConfig.multiplierBps, BPS_DENOMINATOR);
        
        // Update global stats
        unchecked {
            stats.totalVolume += uint128(volume);
            stats.referralCount += 1;
            stats.lastUpdated = uint64(block.timestamp);
            stats.totalEarned += uint128(reward);
        }
        
        // Update per-pool stats for referrer
        referrerPoolVolume[referrer][poolId] += volume;
        
        // Update pool info
        PoolInfo storage pool = poolInfos[poolId];
        unchecked {
            pool.totalReferrals += 1;
            pool.totalVolume += uint128(volume);
        }
        
        // Update global counters
        unchecked {
            totalReferrals += 1;
            totalVolume += volume;
        }
        
        // Check for tier upgrade
        ReferrerTier currentTier = stats.tier;
        ReferrerTier newTier = _calculateTier(stats.totalVolume, stats.referralCount);
        
        if (newTier > currentTier) {
            stats.tier = newTier;
            emit TierUpgrade(referrer, currentTier, newTier);
        }
        
        // Mint reward tokens to referrer
        _mint(referrer, reward);
        
        emit CrossPoolReferral(referrer, swapper, poolId, volume, reward);
        
        return reward;
    }
    
    // ========================================================================
    // REWARD CALCULATION
    // ========================================================================
    
    /// @notice Calculates the base reward for a given volume
    /// @param volume The swap volume
    /// @return reward The calculated reward
    function _calculateReward(uint256 volume) internal view returns (uint256) {
        uint256 reward = FixedPointMathLib.mulDiv(volume, rewardRateBps, BPS_DENOMINATOR);
        
        if (reward < minRewardAmount) {
            return minRewardAmount;
        }
        if (reward > maxRewardAmount) {
            return maxRewardAmount;
        }
        
        return reward;
    }
    
    /// @notice Calculates the tier based on volume and referral count
    /// @param totalVol The referrer's total volume
    /// @param refCount The referrer's referral count
    /// @return tier The calculated tier
    function _calculateTier(uint128 totalVol, uint64 refCount) internal view returns (ReferrerTier) {
        TierThresholds memory platinum = _tierThresholds[ReferrerTier.Platinum];
        if (totalVol >= platinum.minVolume && refCount >= platinum.minReferrals) {
            return ReferrerTier.Platinum;
        }
        
        TierThresholds memory gold = _tierThresholds[ReferrerTier.Gold];
        if (totalVol >= gold.minVolume && refCount >= gold.minReferrals) {
            return ReferrerTier.Gold;
        }
        
        TierThresholds memory silver = _tierThresholds[ReferrerTier.Silver];
        if (totalVol >= silver.minVolume && refCount >= silver.minReferrals) {
            return ReferrerTier.Silver;
        }
        
        return ReferrerTier.Bronze;
    }
    
    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================
    
    /// @inheritdoc IFixerRegistry
    function getReferrerStats(address referrer) external view returns (ReferrerStats memory) {
        return _referrerStats[referrer];
    }
    
    /// @inheritdoc IFixerRegistry
    function getPoolVolume(address referrer, bytes32 poolId) external view returns (uint256) {
        return referrerPoolVolume[referrer][poolId];
    }
    
    /// @inheritdoc IFixerRegistry
    function getPoolInfo(bytes32 poolId) external view returns (PoolInfo memory) {
        return poolInfos[poolId];
    }
    
    /// @inheritdoc IFixerRegistry
    function getTierThresholds(ReferrerTier tier) external view returns (TierThresholds memory) {
        return _tierThresholds[tier];
    }
    
    /// @inheritdoc IFixerRegistry
    function isAuthorizedHook(address hook) external view returns (bool) {
        return authorizedHooks[hook];
    }
    
    /// @inheritdoc IFixerRegistry
    function getProgressToNextTier(address referrer) external view returns (
        ReferrerTier currentTier,
        ReferrerTier nextTier,
        uint256 volumeProgress,
        uint256 referralProgress
    ) {
        ReferrerStats memory stats = _referrerStats[referrer];
        currentTier = stats.tier;
        
        // If already at Platinum, return 100% progress
        if (currentTier == ReferrerTier.Platinum) {
            return (currentTier, currentTier, 10000, 10000);
        }
        
        // Determine next tier
        if (currentTier == ReferrerTier.Bronze) {
            nextTier = ReferrerTier.Silver;
        } else if (currentTier == ReferrerTier.Silver) {
            nextTier = ReferrerTier.Gold;
        } else {
            nextTier = ReferrerTier.Platinum;
        }
        
        TierThresholds memory nextThresholds = _tierThresholds[nextTier];
        
        // Calculate volume progress
        if (nextThresholds.minVolume == 0) {
            volumeProgress = 10000;
        } else {
            volumeProgress = FixedPointMathLib.mulDiv(
                uint256(stats.totalVolume),
                10000,
                nextThresholds.minVolume
            );
            if (volumeProgress > 10000) volumeProgress = 10000;
        }
        
        // Calculate referral progress
        if (nextThresholds.minReferrals == 0) {
            referralProgress = 10000;
        } else {
            referralProgress = FixedPointMathLib.mulDiv(
                uint256(stats.referralCount),
                10000,
                uint256(nextThresholds.minReferrals)
            );
            if (referralProgress > 10000) referralProgress = 10000;
        }
    }
    
    /// @notice Public function to calculate reward for a given volume
    /// @param volume The swap volume
    /// @return The reward amount
    function calculateReward(uint256 volume) external view returns (uint256) {
        if (volume < minSwapAmount) return 0;
        return _calculateReward(volume);
    }
    
    /// @notice Public function to calculate reward with tier multiplier
    /// @param volume The swap volume
    /// @param referrer The referrer address
    /// @return The reward amount including tier multiplier
    function calculateRewardWithTier(uint256 volume, address referrer) external view returns (uint256) {
        if (volume < minSwapAmount) return 0;
        
        uint256 baseReward = _calculateReward(volume);
        ReferrerTier tier = _referrerStats[referrer].tier;
        uint64 multiplier = _tierThresholds[tier].multiplierBps;
        
        return FixedPointMathLib.mulDiv(baseReward, multiplier, BPS_DENOMINATOR);
    }
    
    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================
    
    /// @inheritdoc IFixerRegistry
    function registerHook(address hook, bytes32 poolId) external onlyOwner {
        if (authorizedHooks[hook]) revert HookAlreadyRegistered();
        
        authorizedHooks[hook] = true;
        poolInfos[poolId].hookAddress = hook;
        poolInfos[poolId].active = true;
        
        unchecked {
            hookCount += 1;
        }
        
        emit HookRegistered(hook, poolId);
    }
    
    /// @inheritdoc IFixerRegistry
    function deregisterHook(address hook, bytes32 poolId) external onlyOwner {
        if (!authorizedHooks[hook]) revert HookNotRegistered();
        
        authorizedHooks[hook] = false;
        poolInfos[poolId].active = false;
        
        unchecked {
            hookCount -= 1;
        }
        
        emit HookDeregistered(hook, poolId);
    }
    
    /// @inheritdoc IFixerRegistry
    function setRewardParameters(
        uint256 _minSwapAmount,
        uint256 _rewardRateBps,
        uint256 _maxRewardAmount,
        uint256 _minRewardAmount
    ) external onlyOwner {
        if (_rewardRateBps > BPS_DENOMINATOR) revert InvalidParameter();
        if (_minRewardAmount > _maxRewardAmount) revert InvalidParameter();
        
        minSwapAmount = _minSwapAmount;
        rewardRateBps = _rewardRateBps;
        maxRewardAmount = _maxRewardAmount;
        minRewardAmount = _minRewardAmount;
        
        emit RewardParametersUpdated(_minSwapAmount, _rewardRateBps, _maxRewardAmount, _minRewardAmount);
    }
    
    /// @inheritdoc IFixerRegistry
    function setTierThresholds(ReferrerTier tier, TierThresholds calldata thresholds) external onlyOwner {
        if (thresholds.multiplierBps > 100_000) revert InvalidParameter(); // Max 10x
        
        _tierThresholds[tier] = thresholds;
        
        emit TierThresholdsUpdated(tier, thresholds);
    }
}
