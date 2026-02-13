// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// Uniswap v4 Core
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

// Uniswap v4 Periphery
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Token Standard (Solmate for gas efficiency)
import {ERC20} from "solmate/src/tokens/ERC20.sol";

// Solady for gas-optimized utilities
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerHook
/// @author Aaryan Guglani
/// @notice On-chain affiliate rewards for Uniswap v4 pools
/// @dev "Everybody pays the Fixer." - A learning-focused implementation.
/// 
/// Architecture:
/// - Inherits BaseHook for Uniswap v4 hook functionality
/// - Inherits ERC20 to act as the reward token itself (FIX token)
/// - Inherits Ownable for parameter management
/// - Only enables afterSwap permission for minimal gas overhead
///
/// @custom:security-note Unsupported Token Types:
///   - Fee-on-transfer tokens: Volume calculation uses BalanceDelta amounts,
///     not actual received amounts. Rewards may be overstated.
///   - Rebasing tokens: Balance changes outside swaps are not tracked.
///   - ERC-777 tokens: Callback hooks could interfere with gas estimates.
///   - Pausable/blocklist tokens: May cause unexpected swap reverts.
///   These do NOT pose funds-at-risk since this hook is observation-only
///   (no delta modification), but reward accuracy may be affected.
///
/// v1.1 Features:
/// - Dynamic rewards based on swap volume
/// - Minimum volume threshold to prevent Sybil farming
/// - Maximum reward cap to prevent extreme payouts
/// - Configurable parameters (governance-ready)
///
/// Workflow:
/// 1. User initiates swap with encoded referrer address in hookData
/// 2. PoolManager executes swap, then calls afterSwap on this hook
/// 3. Hook decodes referrer, validates (not zero, not self-referral)
/// 4. Calculates reward based on swap volume
/// 5. If valid and above threshold, mints reward tokens to referrer
contract FixerHook is BaseHook, ERC20, Ownable {
    using PoolIdLibrary for PoolKey;
    
    // ========================================================================
    // TYPES
    // ========================================================================
    
    /// @notice Per-pool reward configuration
    /// @dev Packed into 2 storage slots for gas efficiency
    struct PoolRewardConfig {
        uint128 minSwapAmount;     // Minimum swap volume for rewards
        uint64 rewardRateBps;      // Reward rate in basis points
        uint64 quoteTokenIndex;    // 0 = token0 is quote, 1 = token1 is quote
        uint128 maxRewardAmount;   // Maximum reward per swap
        uint128 minRewardAmount;   // Minimum reward when threshold met
    }
    
    /// @notice Referrer tier levels for the tiered rewards system
    /// @dev Higher tiers earn higher reward multipliers
    enum ReferrerTier {
        Bronze,    // Default tier, 1.0x multiplier
        Silver,    // 1.25x multiplier
        Gold,      // 1.5x multiplier
        Platinum   // 2.0x multiplier
    }
    
    /// @notice Thresholds and multiplier for each tier
    /// @dev Packed for gas efficiency
    struct TierThresholds {
        uint128 minVolume;       // Minimum cumulative volume to qualify
        uint64 minReferrals;     // Minimum referral count to qualify
        uint64 multiplierBps;    // Reward multiplier in bps (10000 = 1.0x)
    }
    
    /// @notice Per-referrer statistics and current tier
    /// @dev Packed into 2 storage slots for gas efficiency
    /// Slot 1: totalVolume (16 bytes) + referralCount (8 bytes) + lastUpdated (8 bytes)
    /// Slot 2: totalEarned (16 bytes) + tier (1 byte) + padding
    struct ReferrerStats {
        uint128 totalVolume;     // Cumulative volume referred
        uint64 referralCount;    // Number of successful referrals
        uint64 lastUpdated;      // Timestamp of last activity
        uint128 totalEarned;     // Total FIX tokens earned
        ReferrerTier tier;       // Current tier level
    }
    
    // ========================================================================
    // EVENTS
    // ========================================================================
    
    /// @notice Emitted when a referral reward is issued
    /// @param referrer The address that received the reward
    /// @param swapper The address that initiated the swap (tx.origin)
    /// @param poolId The pool where the swap occurred
    /// @param volume The swap volume used for reward calculation (in quote token)
    /// @param reward The amount of FIX tokens minted
    event ReferralReward(
        address indexed referrer,
        address indexed swapper,
        PoolId indexed poolId,
        uint256 volume,
        uint256 reward
    );
    
    /// @notice Emitted when global reward parameters are updated
    /// @param minSwapAmount The new minimum swap volume threshold
    /// @param rewardRateBps The new reward rate in basis points
    /// @param maxRewardAmount The new maximum reward cap
    /// @param minRewardAmount The new minimum reward floor
    event RewardParametersUpdated(
        uint256 minSwapAmount,
        uint256 rewardRateBps,
        uint256 maxRewardAmount,
        uint256 minRewardAmount
    );
    
    /// @notice Emitted when per-pool configuration is set
    /// @param poolId The pool being configured
    /// @param config The new configuration
    event PoolConfigured(PoolId indexed poolId, PoolRewardConfig config);
    
    /// @notice Emitted when per-pool configuration is removed
    /// @param poolId The pool being unconfigured
    event PoolConfigRemoved(PoolId indexed poolId);
    
    /// @notice Emitted when a referrer's tier is upgraded
    /// @param referrer The address that was upgraded
    /// @param fromTier The previous tier
    /// @param toTier The new tier
    event TierUpgrade(
        address indexed referrer,
        ReferrerTier indexed fromTier,
        ReferrerTier indexed toTier
    );
    
    /// @notice Emitted when tier thresholds are updated
    /// @param tier The tier being updated
    /// @param thresholds The new thresholds
    event TierThresholdsUpdated(ReferrerTier indexed tier, TierThresholds thresholds);
    
    // ========================================================================
    // ERRORS
    // ========================================================================
    
    /// @notice Thrown when an invalid parameter is provided
    error InvalidParameter();
    
    // ========================================================================
    // CONSTANTS
    // ========================================================================
    
    /// @notice Legacy fixed reward amount (for reference, now using dynamic calculation)
    /// @dev Kept for backwards compatibility reference
    uint256 public constant REWARD_AMOUNT = 10 * 1e18;
    
    /// @notice Maximum basis points (100%)
    uint256 private constant BPS_DENOMINATOR = 10000;
    
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================
    
    /// @notice Per-pool reward configurations
    /// @dev If not set, falls back to global defaults
    mapping(PoolId => PoolRewardConfig) public poolConfigs;
    
    /// @notice Tracks if a pool has custom configuration
    mapping(PoolId => bool) public hasPoolConfig;
    
    /// @notice Per-referrer statistics and tier info
    mapping(address => ReferrerStats) public referrerStats;
    
    /// @notice Thresholds and multipliers for each tier level
    mapping(ReferrerTier => TierThresholds) public tierThresholds;
    
    /// @notice Global minimum swap volume required to earn rewards (in token units)
    /// @dev Prevents Sybil farming with dust swaps. Used when no per-pool config.
    uint256 public minSwapAmount;
    
    /// @notice Global reward rate in basis points (1 bps = 0.01%)
    /// @dev 10 bps = 0.1%, meaning 0.1% of swap volume as reward
    uint256 public rewardRateBps;
    
    /// @notice Global maximum reward that can be earned per swap
    /// @dev Prevents extreme payouts on large swaps
    uint256 public maxRewardAmount;
    
    /// @notice Global minimum reward when volume threshold is met
    /// @dev Ensures meaningful rewards even for moderate swaps
    uint256 public minRewardAmount;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /// @notice Initializes the FixerHook with PoolManager and token details
    /// @param _manager Address of the Uniswap v4 PoolManager
    /// @param _owner Address of the contract owner for parameter management
    /// @dev Hook address must have correct permission bits set (afterSwap = bit 7)
    constructor(IPoolManager _manager, address _owner) 
        BaseHook(_manager) 
        ERC20("Fixer Token", "FIX", 18) 
    {
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
    /// @dev Called in constructor. Can be updated later via setTierThresholds
    function _initializeTiers() internal {
        // Bronze: Default tier, no requirements, 1.0x multiplier
        tierThresholds[ReferrerTier.Bronze] = TierThresholds({
            minVolume: 0,
            minReferrals: 0,
            multiplierBps: 10000  // 1.0x
        });
        
        // Silver: 10k volume, 10 referrals, 1.25x multiplier
        tierThresholds[ReferrerTier.Silver] = TierThresholds({
            minVolume: 10_000 * 1e18,
            minReferrals: 10,
            multiplierBps: 12500  // 1.25x
        });
        
        // Gold: 100k volume, 50 referrals, 1.5x multiplier
        tierThresholds[ReferrerTier.Gold] = TierThresholds({
            minVolume: 100_000 * 1e18,
            minReferrals: 50,
            multiplierBps: 15000  // 1.5x
        });
        
        // Platinum: 1M volume, 200 referrals, 2.0x multiplier
        tierThresholds[ReferrerTier.Platinum] = TierThresholds({
            minVolume: 1_000_000 * 1e18,
            minReferrals: 200,
            multiplierBps: 20000  // 2.0x
        });
    }
    
    // ========================================================================
    // HOOK CONFIGURATION
    // ========================================================================
    
    /// @notice Defines which hook lifecycle functions should be called
    /// @dev Only afterSwap is enabled to minimize gas overhead
    /// @return Permissions struct with all flags set appropriately
    function getHookPermissions() 
        public 
        pure 
        override 
        returns (Hooks.Permissions memory) 
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,                    // ENABLED: Issue rewards after swap
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    // ========================================================================
    // HOOK LOGIC
    // ========================================================================
    
    /// @notice Called by PoolManager after each swap to process referral rewards
    /// @dev This is the core logic that validates and rewards referrers
    /// 
    /// Validation steps:
    /// 1. Check if hookData contains referrer (length > 0)
    /// 2. Decode referrer address from hookData
    /// 3. Ensure referrer is not zero address
    /// 4. Ensure referrer is not the transaction originator (anti-gaming)
    /// 5. Calculate swap volume and check against minimum threshold
    /// 6. Calculate dynamic reward based on volume
    /// 7. If all checks pass, mint reward tokens to referrer
    ///
    /// @param sender The address that called swap (typically a router contract)
    /// @param key The pool's identifying key (unused in current implementation)
    /// @param params The swap parameters (unused in current implementation)
    /// @param delta The balance changes from the swap
    /// @param hookData Encoded referrer address: abi.encode(address referrer)
    /// @return selector The afterSwap function selector for validation
    /// @return deltaUnspecified The delta modification (always 0, we don't modify amounts)
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        
        // ====================================================================
        // STEP 1: Check if referral data exists
        // ====================================================================
        // If hookData is empty, this is a normal swap without referral intent.
        // Skip all processing and return early to save gas.
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 2: Decode the referrer address
        // ====================================================================
        // hookData format: abi.encode(address referrer)
        // This produces a 32-byte padded address representation.
        // If hookData is malformed, abi.decode will revert.
        address referrer = abi.decode(hookData, (address));
        
        // ====================================================================
        // STEP 3: Validate - Check for zero address
        // ====================================================================
        // Minting to address(0) would burn tokens. Reject this case.
        if (referrer == address(0)) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 4: Validate - Prevent self-referral
        // ====================================================================
        // Anti-gaming measure: Users should not be able to refer themselves.
        // 
        // Why tx.origin instead of sender?
        // - `sender` is often a router contract (SwapRouter), not the user
        // - `tx.origin` gives us the actual EOA that initiated the transaction
        // - This is safe for anti-gaming (not for authentication)
        //
        // ⚠️ KNOWN LIMITATION (V1 only):
        // tx.origin is unreliable for ERC-4337 Smart Accounts and bundled
        // transactions. V2 (FixerHookV2) implements the Trusted Router Pattern
        // which resolves the actual user via IMsgSender(router).msgSender().
        // Migrate to V2 for production deployments requiring accurate user tracking.
        //
        // Limitation: Does not prevent cross-wallet referral (Sybil attack)
        // Future versions could add volume thresholds to mitigate.
        if (referrer == tx.origin) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 5: Get pool configuration (per-pool or global fallback)
        // ====================================================================
        PoolId poolId = key.toId();
        (
            uint256 poolMinSwap,
            uint256 poolRewardRate,
            uint256 poolMaxReward,
            uint256 poolMinReward,
            uint256 quoteTokenIdx
        ) = _getPoolConfig(poolId);
        
        // ====================================================================
        // STEP 6: Calculate swap volume using quote token
        // ====================================================================
        // Use the configured quote token for consistent volume measurement
        // This addresses the token decimals issue across different pools
        uint256 volume = _calculateSwapVolume(delta, quoteTokenIdx);
        
        // ====================================================================
        // STEP 7: Check minimum volume threshold
        // ====================================================================
        // Swaps below the minimum threshold don't earn rewards.
        // This prevents Sybil farming with dust amounts.
        if (volume < poolMinSwap) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 8: Calculate base reward with tier multiplier
        // ====================================================================
        uint256 baseReward = _calculateReward(volume, poolRewardRate, poolMinReward, poolMaxReward);
        
        // Get referrer's current tier and apply multiplier
        ReferrerStats storage stats = referrerStats[referrer];
        TierThresholds memory tierConfig = tierThresholds[stats.tier];
        
        // Apply tier multiplier: reward * multiplierBps / 10000
        uint256 reward = FixedPointMathLib.mulDiv(baseReward, tierConfig.multiplierBps, BPS_DENOMINATOR);
        
        // ====================================================================
        // STEP 9: Update referrer statistics
        // ====================================================================
        // Update stats before tier check (tier based on updated stats)
        stats.totalVolume += uint128(volume);
        stats.referralCount += 1;
        stats.lastUpdated = uint64(block.timestamp);
        stats.totalEarned += uint128(reward);
        
        // ====================================================================
        // STEP 10: Check for tier upgrade
        // ====================================================================
        ReferrerTier currentTier = stats.tier;
        ReferrerTier newTier = _calculateTier(stats.totalVolume, stats.referralCount);
        
        if (newTier > currentTier) {
            stats.tier = newTier;
            emit TierUpgrade(referrer, currentTier, newTier);
        }
        
        // ====================================================================
        // STEP 11: Mint reward tokens
        // ====================================================================
        // All validation passed. Mint calculated reward to the referrer.
        // _mint is inherited from Solmate's ERC20 implementation.
        _mint(referrer, reward);
        
        // Emit event for indexing and tracking
        emit ReferralReward(referrer, tx.origin, poolId, volume, reward);
        
        // ====================================================================
        // STEP 12: Return success
        // ====================================================================
        // - Selector: Required for hook validation by PoolManager
        // - int128(0): No delta modification (we don't take fees or modify amounts)
        return (this.afterSwap.selector, 0);
    }
    
    // ========================================================================
    // CONFIGURATION HELPERS
    // ========================================================================
    
    /// @notice Gets the effective configuration for a pool
    /// @dev Returns per-pool config if set, otherwise global defaults
    /// @param poolId The pool identifier
    /// @return minSwap Minimum swap amount for rewards
    /// @return rewardRate Reward rate in basis points
    /// @return maxReward Maximum reward per swap
    /// @return minReward Minimum reward when threshold met
    /// @return quoteTokenIdx Index of quote token (0 or 1)
    function _getPoolConfig(PoolId poolId) internal view returns (
        uint256 minSwap,
        uint256 rewardRate,
        uint256 maxReward,
        uint256 minReward,
        uint256 quoteTokenIdx
    ) {
        if (hasPoolConfig[poolId]) {
            PoolRewardConfig memory config = poolConfigs[poolId];
            return (
                config.minSwapAmount,
                config.rewardRateBps,
                config.maxRewardAmount,
                config.minRewardAmount,
                config.quoteTokenIndex
            );
        }
        // Fallback to global defaults (quote token defaults to token1 - typically stablecoin)
        return (minSwapAmount, rewardRateBps, maxRewardAmount, minRewardAmount, 1);
    }
    
    // ========================================================================
    // REWARD CALCULATION
    // ========================================================================
    
    /// @notice Calculates the swap volume from balance delta using quote token
    /// @dev Uses the configured quote token for consistent volume across pools
    /// 
    /// IMPORTANT: This fixes the volume calculation issue where different token
    /// decimals could lead to inconsistent volume measurements. By using a
    /// designated "quote token" (typically a stablecoin like USDC), we ensure
    /// volume is measured consistently regardless of the base token's decimals.
    ///
    /// @param delta The balance changes from the swap
    /// @param quoteTokenIndex Which token is the quote (0 = token0, 1 = token1)
    /// @return volume The calculated swap volume in quote token units
    function _calculateSwapVolume(BalanceDelta delta, uint256 quoteTokenIndex) internal pure returns (uint256) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        
        // Select the quote token amount for volume calculation
        // This ensures consistent volume measurement across pools with different token pairs
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        
        // Convert to absolute value
        // forge-lint: disable-next-line(unsafe-typecast)
        // Casting is safe: we check for negative first, and int128 range fits in uint128
        return quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
    }
    
    /// @notice Calculates the reward based on swap volume with configurable parameters
    /// @dev Uses FixedPointMathLib for precise calculation
    /// @param volume The swap volume
    /// @param rewardRate Reward rate in basis points
    /// @param minReward Minimum reward floor
    /// @param maxReward Maximum reward cap
    /// @return reward The calculated reward, bounded by min/max
    function _calculateReward(
        uint256 volume,
        uint256 rewardRate,
        uint256 minReward,
        uint256 maxReward
    ) internal pure returns (uint256) {
        // Calculate proportional reward: volume * rewardRateBps / 10000
        uint256 reward = FixedPointMathLib.mulDiv(volume, rewardRate, BPS_DENOMINATOR);
        
        // Apply minimum floor
        if (reward < minReward) {
            return minReward;
        }
        
        // Apply maximum cap
        if (reward > maxReward) {
            return maxReward;
        }
        
        return reward;
    }
    
    /// @notice Public view function to calculate reward for a given volume (uses global params)
    /// @dev Useful for frontend integration and testing
    /// @param volume The swap volume to calculate reward for
    /// @return The reward that would be issued for this volume
    function calculateReward(uint256 volume) external view returns (uint256) {
        if (volume < minSwapAmount) {
            return 0;
        }
        return _calculateReward(volume, rewardRateBps, minRewardAmount, maxRewardAmount);
    }
    
    /// @notice Public view function to calculate reward for a specific pool
    /// @dev Uses per-pool config if available, otherwise global defaults
    /// @param poolId The pool identifier
    /// @param volume The swap volume to calculate reward for
    /// @return The reward that would be issued for this volume in this pool
    function calculateRewardForPool(PoolId poolId, uint256 volume) external view returns (uint256) {
        (
            uint256 poolMinSwap,
            uint256 poolRewardRate,
            uint256 poolMaxReward,
            uint256 poolMinReward,
        ) = _getPoolConfig(poolId);
        
        if (volume < poolMinSwap) {
            return 0;
        }
        return _calculateReward(volume, poolRewardRate, poolMinReward, poolMaxReward);
    }
    
    // ========================================================================
    // TIER SYSTEM
    // ========================================================================
    
    /// @notice Calculates which tier a referrer qualifies for based on their stats
    /// @dev Checks from highest to lowest tier, returns first qualifying tier
    /// @param totalVolume Referrer's cumulative volume
    /// @param referralCount Referrer's total referral count
    /// @return tier The highest tier the referrer qualifies for
    function _calculateTier(uint128 totalVolume, uint64 referralCount) internal view returns (ReferrerTier) {
        // Check tiers from highest to lowest
        TierThresholds memory platinum = tierThresholds[ReferrerTier.Platinum];
        if (totalVolume >= platinum.minVolume && referralCount >= platinum.minReferrals) {
            return ReferrerTier.Platinum;
        }
        
        TierThresholds memory gold = tierThresholds[ReferrerTier.Gold];
        if (totalVolume >= gold.minVolume && referralCount >= gold.minReferrals) {
            return ReferrerTier.Gold;
        }
        
        TierThresholds memory silver = tierThresholds[ReferrerTier.Silver];
        if (totalVolume >= silver.minVolume && referralCount >= silver.minReferrals) {
            return ReferrerTier.Silver;
        }
        
        return ReferrerTier.Bronze;
    }
    
    /// @notice Gets a referrer's current stats and tier info
    /// @dev Useful for frontend integration
    /// @param referrer The referrer address to query
    /// @return stats The referrer's statistics
    function getReferrerStats(address referrer) external view returns (ReferrerStats memory) {
        return referrerStats[referrer];
    }
    
    /// @notice Gets progress toward the next tier
    /// @dev Returns volume and referral progress as percentages (0-100%)
    /// @param referrer The referrer address to query
    /// @return currentTier The referrer's current tier
    /// @return nextTier The next tier (or current if at Platinum)
    /// @return volumeProgress Percentage progress toward next tier volume (0-10000 bps)
    /// @return referralProgress Percentage progress toward next tier referrals (0-10000 bps)
    function getProgressToNextTier(address referrer) external view returns (
        ReferrerTier currentTier,
        ReferrerTier nextTier,
        uint256 volumeProgress,
        uint256 referralProgress
    ) {
        ReferrerStats memory stats = referrerStats[referrer];
        currentTier = stats.tier;
        
        // If already at Platinum, return 100% progress
        if (currentTier == ReferrerTier.Platinum) {
            return (currentTier, currentTier, 10000, 10000);
        }
        
        // Get next tier
        if (currentTier == ReferrerTier.Bronze) {
            nextTier = ReferrerTier.Silver;
        } else if (currentTier == ReferrerTier.Silver) {
            nextTier = ReferrerTier.Gold;
        } else {
            nextTier = ReferrerTier.Platinum;
        }
        
        TierThresholds memory nextThresholds = tierThresholds[nextTier];
        
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
    
    /// @notice Gets the tier multiplier for a specific referrer
    /// @dev Useful for calculating expected rewards
    /// @param referrer The referrer address
    /// @return multiplierBps The tier's reward multiplier in basis points
    function getTierMultiplier(address referrer) external view returns (uint256) {
        ReferrerTier tier = referrerStats[referrer].tier;
        return tierThresholds[tier].multiplierBps;
    }
    
    /// @notice Gets the thresholds for a specific tier
    /// @param tier The tier to query
    /// @return The tier's thresholds
    function getTierThresholds(ReferrerTier tier) external view returns (TierThresholds memory) {
        return tierThresholds[tier];
    }
    
    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================
    
    /// @notice Configures reward parameters for a specific pool
    /// @dev Only callable by contract owner. Allows different pools to have
    ///      different reward settings, addressing the multi-pool configuration issue.
    /// @param poolId The pool to configure
    /// @param config The reward configuration for this pool
    function setPoolConfig(PoolId poolId, PoolRewardConfig calldata config) external onlyOwner {
        // Validate parameters
        if (config.rewardRateBps > BPS_DENOMINATOR) revert InvalidParameter();
        if (config.minRewardAmount > config.maxRewardAmount) revert InvalidParameter();
        if (config.quoteTokenIndex > 1) revert InvalidParameter();
        
        poolConfigs[poolId] = config;
        hasPoolConfig[poolId] = true;
        
        emit PoolConfigured(poolId, config);
    }
    
    /// @notice Removes per-pool configuration, falling back to global defaults
    /// @dev Only callable by contract owner
    /// @param poolId The pool to unconfigure
    function removePoolConfig(PoolId poolId) external onlyOwner {
        delete poolConfigs[poolId];
        hasPoolConfig[poolId] = false;
        emit PoolConfigRemoved(poolId);
    }
    
    /// @notice Updates global reward parameters (used when no per-pool config)
    /// @dev Only callable by contract owner
    /// @param _minSwapAmount New minimum swap volume threshold
    /// @param _rewardRateBps New reward rate in basis points
    /// @param _maxRewardAmount New maximum reward cap
    /// @param _minRewardAmount New minimum reward floor
    function setRewardParameters(
        uint256 _minSwapAmount,
        uint256 _rewardRateBps,
        uint256 _maxRewardAmount,
        uint256 _minRewardAmount
    ) external onlyOwner {
        // Validate parameters
        if (_rewardRateBps > BPS_DENOMINATOR) revert InvalidParameter();
        if (_minRewardAmount > _maxRewardAmount) revert InvalidParameter();
        
        minSwapAmount = _minSwapAmount;
        rewardRateBps = _rewardRateBps;
        maxRewardAmount = _maxRewardAmount;
        minRewardAmount = _minRewardAmount;
        
        emit RewardParametersUpdated(_minSwapAmount, _rewardRateBps, _maxRewardAmount, _minRewardAmount);
    }
    
    /// @notice Updates thresholds for a specific tier
    /// @dev Only callable by contract owner
    /// @param tier The tier to update
    /// @param thresholds The new thresholds for this tier
    function setTierThresholds(ReferrerTier tier, TierThresholds calldata thresholds) external onlyOwner {
        // Validate multiplier is reasonable (0-1000%, i.e., 0-100_000 bps)
        if (thresholds.multiplierBps > 100_000) revert InvalidParameter();
        
        tierThresholds[tier] = thresholds;
        emit TierThresholdsUpdated(tier, thresholds);
    }
}
