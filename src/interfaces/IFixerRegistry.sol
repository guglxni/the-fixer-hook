// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title IFixerRegistry Interface
/// @notice Interface for the central Fixer Registry contract
/// @dev Used by FixerHookV2 contracts to record referrals across multiple pools
interface IFixerRegistry {
    
    // ========================================================================
    // TYPES
    // ========================================================================
    
    /// @notice Referrer tier levels
    enum ReferrerTier {
        Bronze,    // 1.0x multiplier
        Silver,    // 1.25x multiplier
        Gold,      // 1.5x multiplier
        Platinum   // 2.0x multiplier
    }
    
    /// @notice Tier thresholds and multiplier configuration
    struct TierThresholds {
        uint128 minVolume;       // Minimum cumulative volume to qualify
        uint64 minReferrals;     // Minimum referral count to qualify
        uint64 multiplierBps;    // Reward multiplier in bps (10000 = 1.0x)
    }
    
    /// @notice Per-referrer statistics
    struct ReferrerStats {
        uint128 totalVolume;     // Cumulative volume across all pools
        uint64 referralCount;    // Total referral count
        uint64 lastUpdated;      // Timestamp of last activity
        uint128 totalEarned;     // Total FIX tokens earned
        ReferrerTier tier;       // Current tier level
    }
    
    /// @notice Per-pool information
    struct PoolInfo {
        address hookAddress;     // Address of the hook for this pool
        bool active;             // Whether the pool is active
        uint64 totalReferrals;   // Total referrals in this pool
        uint128 totalVolume;     // Total volume in this pool
    }
    
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
        ReferrerTier indexed fromTier,
        ReferrerTier indexed toTier
    );
    
    /// @notice Emitted when tier thresholds are updated
    event TierThresholdsUpdated(ReferrerTier indexed tier, TierThresholds thresholds);
    
    /// @notice Emitted when reward parameters are updated
    event RewardParametersUpdated(
        uint256 minSwapAmount,
        uint256 rewardRateBps,
        uint256 maxRewardAmount,
        uint256 minRewardAmount
    );
    
    // ========================================================================
    // ERRORS
    // ========================================================================
    
    /// @notice Thrown when an unauthorized hook attempts to record a referral
    error UnauthorizedHook();
    
    /// @notice Thrown when an invalid referrer address is provided
    error InvalidReferrer();
    
    /// @notice Thrown when self-referral is attempted
    error SelfReferral();
    
    /// @notice Thrown when an invalid parameter is provided
    error InvalidParameter();
    
    /// @notice Thrown when a hook is already registered
    error HookAlreadyRegistered();
    
    /// @notice Thrown when a hook is not registered
    error HookNotRegistered();
    
    // ========================================================================
    // CORE FUNCTIONS
    // ========================================================================
    
    /// @notice Records a referral from an authorized hook
    /// @dev Only callable by authorized hooks
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
    ) external returns (uint256 reward);
    
    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================
    
    /// @notice Gets a referrer's comprehensive stats
    /// @param referrer The referrer address
    /// @return stats The referrer's statistics
    function getReferrerStats(address referrer) external view returns (ReferrerStats memory stats);
    
    /// @notice Gets a referrer's volume in a specific pool
    /// @param referrer The referrer address
    /// @param poolId The pool identifier
    /// @return volume The referrer's volume in the pool
    function getPoolVolume(address referrer, bytes32 poolId) external view returns (uint256 volume);
    
    /// @notice Gets pool information
    /// @param poolId The pool identifier
    /// @return info The pool's information
    function getPoolInfo(bytes32 poolId) external view returns (PoolInfo memory info);
    
    /// @notice Gets the tier thresholds for a specific tier
    /// @param tier The tier to query
    /// @return thresholds The tier's thresholds
    function getTierThresholds(ReferrerTier tier) external view returns (TierThresholds memory thresholds);
    
    /// @notice Checks if a hook is authorized
    /// @param hook The hook address to check
    /// @return authorized Whether the hook is authorized
    function isAuthorizedHook(address hook) external view returns (bool authorized);
    
    /// @notice Gets progress toward the next tier
    /// @param referrer The referrer address
    /// @return currentTier The current tier
    /// @return nextTier The next tier
    /// @return volumeProgress Progress toward volume requirement (0-10000 bps)
    /// @return referralProgress Progress toward referral requirement (0-10000 bps)
    function getProgressToNextTier(address referrer) external view returns (
        ReferrerTier currentTier,
        ReferrerTier nextTier,
        uint256 volumeProgress,
        uint256 referralProgress
    );
    
    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================
    
    /// @notice Registers a hook for a specific pool
    /// @param hook The hook address
    /// @param poolId The pool identifier
    function registerHook(address hook, bytes32 poolId) external;
    
    /// @notice Deregisters a hook
    /// @param hook The hook address
    /// @param poolId The pool identifier
    function deregisterHook(address hook, bytes32 poolId) external;
    
    /// @notice Sets the reward parameters
    /// @param minSwapAmount Minimum swap amount for rewards
    /// @param rewardRateBps Reward rate in basis points
    /// @param maxRewardAmount Maximum reward per swap
    /// @param minRewardAmount Minimum reward per swap
    function setRewardParameters(
        uint256 minSwapAmount,
        uint256 rewardRateBps,
        uint256 maxRewardAmount,
        uint256 minRewardAmount
    ) external;
    
    /// @notice Sets the thresholds for a specific tier
    /// @param tier The tier to update
    /// @param thresholds The new thresholds
    function setTierThresholds(ReferrerTier tier, TierThresholds calldata thresholds) external;
}
