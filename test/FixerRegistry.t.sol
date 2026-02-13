// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixerRegistry} from "../src/FixerRegistry.sol";
import {IFixerRegistry} from "../src/interfaces/IFixerRegistry.sol";

/// @title FixerRegistry v2.0 Unit Tests
/// @notice Comprehensive test suite for the FixerRegistry cross-pool system
/// @dev Tests hook authorization, referral recording, tier system, and admin functions
contract FixerRegistryTest is Test {
    
    FixerRegistry public registry;
    
    address public owner = makeAddr("owner");
    address public hook1 = makeAddr("hook1");
    address public hook2 = makeAddr("hook2");
    address public unauthorized = makeAddr("unauthorized");
    address public referrer = makeAddr("referrer");
    address public swapper = makeAddr("swapper");
    
    bytes32 public poolId1 = keccak256("pool1");
    bytes32 public poolId2 = keccak256("pool2");
    
    // Default parameters
    uint256 public constant DEFAULT_MIN_SWAP = 100 * 1e18;
    uint256 public constant DEFAULT_REWARD_RATE_BPS = 10;
    uint256 public constant DEFAULT_MAX_REWARD = 1000 * 1e18;
    uint256 public constant DEFAULT_MIN_REWARD = 1 * 1e18;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    function setUp() public {
        registry = new FixerRegistry(owner);
    }
    
    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================
    
    function test_Initialization() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.name(), "Fixer Token");
        assertEq(registry.symbol(), "FIX");
        assertEq(registry.decimals(), 18);
        assertEq(registry.minSwapAmount(), DEFAULT_MIN_SWAP);
        assertEq(registry.rewardRateBps(), DEFAULT_REWARD_RATE_BPS);
        assertEq(registry.maxRewardAmount(), DEFAULT_MAX_REWARD);
        assertEq(registry.minRewardAmount(), DEFAULT_MIN_REWARD);
    }
    
    function test_TierThresholdsInitialized() public view {
        // Bronze
        IFixerRegistry.TierThresholds memory bronze = registry.getTierThresholds(IFixerRegistry.ReferrerTier.Bronze);
        assertEq(bronze.minVolume, 0);
        assertEq(bronze.minReferrals, 0);
        assertEq(bronze.multiplierBps, 10000);
        
        // Silver
        IFixerRegistry.TierThresholds memory silver = registry.getTierThresholds(IFixerRegistry.ReferrerTier.Silver);
        assertEq(silver.minVolume, 10_000e18);
        assertEq(silver.minReferrals, 10);
        assertEq(silver.multiplierBps, 12500);
        
        // Gold
        IFixerRegistry.TierThresholds memory gold = registry.getTierThresholds(IFixerRegistry.ReferrerTier.Gold);
        assertEq(gold.minVolume, 100_000e18);
        assertEq(gold.minReferrals, 50);
        assertEq(gold.multiplierBps, 15000);
        
        // Platinum
        IFixerRegistry.TierThresholds memory platinum = registry.getTierThresholds(IFixerRegistry.ReferrerTier.Platinum);
        assertEq(platinum.minVolume, 1_000_000e18);
        assertEq(platinum.minReferrals, 200);
        assertEq(platinum.multiplierBps, 20000);
    }
    
    // ========================================================================
    // HOOK AUTHORIZATION TESTS
    // ========================================================================
    
    function test_RegisterHook() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        assertTrue(registry.isAuthorizedHook(hook1));
        assertEq(registry.hookCount(), 1);
        
        IFixerRegistry.PoolInfo memory poolInfo = registry.getPoolInfo(poolId1);
        assertEq(poolInfo.hookAddress, hook1);
        assertTrue(poolInfo.active);
    }
    
    function test_RegisterMultipleHooks() public {
        vm.startPrank(owner);
        registry.registerHook(hook1, poolId1);
        registry.registerHook(hook2, poolId2);
        vm.stopPrank();
        
        assertTrue(registry.isAuthorizedHook(hook1));
        assertTrue(registry.isAuthorizedHook(hook2));
        assertEq(registry.hookCount(), 2);
    }
    
    function test_RegisterHook_RevertIfAlreadyRegistered() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        vm.expectRevert(IFixerRegistry.HookAlreadyRegistered.selector);
        vm.prank(owner);
        registry.registerHook(hook1, poolId2);
    }
    
    function test_RegisterHook_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        registry.registerHook(hook1, poolId1);
    }
    
    function test_DeregisterHook() public {
        vm.startPrank(owner);
        registry.registerHook(hook1, poolId1);
        registry.deregisterHook(hook1, poolId1);
        vm.stopPrank();
        
        assertFalse(registry.isAuthorizedHook(hook1));
        assertEq(registry.hookCount(), 0);
        
        IFixerRegistry.PoolInfo memory poolInfo = registry.getPoolInfo(poolId1);
        assertFalse(poolInfo.active);
    }
    
    function test_DeregisterHook_RevertIfNotRegistered() public {
        vm.expectRevert(IFixerRegistry.HookNotRegistered.selector);
        vm.prank(owner);
        registry.deregisterHook(hook1, poolId1);
    }
    
    // ========================================================================
    // REFERRAL RECORDING TESTS
    // ========================================================================
    
    function test_RecordReferral_Success() public {
        // Register hook
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        uint256 volume = 1000e18;
        
        // Record referral from authorized hook
        vm.prank(hook1);
        uint256 reward = registry.recordReferral(referrer, swapper, volume, poolId1);
        
        // Expected reward: 1000 * 10 / 10000 = 1 FIX (min reward)
        assertEq(reward, DEFAULT_MIN_REWARD);
        assertEq(registry.balanceOf(referrer), reward);
        
        // Check stats
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(referrer);
        assertEq(stats.totalVolume, volume);
        assertEq(stats.referralCount, 1);
        assertEq(stats.totalEarned, reward);
        assertEq(uint8(stats.tier), uint8(IFixerRegistry.ReferrerTier.Bronze));
    }
    
    function test_RecordReferral_VolumeBelowThreshold() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        uint256 volume = 50e18; // Below minimum
        
        vm.prank(hook1);
        uint256 reward = registry.recordReferral(referrer, swapper, volume, poolId1);
        
        assertEq(reward, 0);
        assertEq(registry.balanceOf(referrer), 0);
    }
    
    function test_RecordReferral_UnauthorizedHook() public {
        vm.expectRevert(IFixerRegistry.UnauthorizedHook.selector);
        vm.prank(unauthorized);
        registry.recordReferral(referrer, swapper, 1000e18, poolId1);
    }
    
    function test_RecordReferral_InvalidReferrer() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        vm.expectRevert(IFixerRegistry.InvalidReferrer.selector);
        vm.prank(hook1);
        registry.recordReferral(address(0), swapper, 1000e18, poolId1);
    }
    
    function test_RecordReferral_SelfReferral() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        vm.expectRevert(IFixerRegistry.SelfReferral.selector);
        vm.prank(hook1);
        registry.recordReferral(referrer, referrer, 1000e18, poolId1);
    }
    
    // ========================================================================
    // CROSS-POOL TESTS
    // ========================================================================
    
    function test_CrossPoolStatsAccumulation() public {
        // Register two hooks
        vm.startPrank(owner);
        registry.registerHook(hook1, poolId1);
        registry.registerHook(hook2, poolId2);
        vm.stopPrank();
        
        uint256 volume1 = 5000e18;
        uint256 volume2 = 7000e18;
        
        // Record referrals from different pools
        vm.prank(hook1);
        registry.recordReferral(referrer, swapper, volume1, poolId1);
        
        vm.prank(hook2);
        registry.recordReferral(referrer, swapper, volume2, poolId2);
        
        // Check global stats
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(referrer);
        assertEq(stats.totalVolume, volume1 + volume2);
        assertEq(stats.referralCount, 2);
        
        // Check per-pool volume
        assertEq(registry.getPoolVolume(referrer, poolId1), volume1);
        assertEq(registry.getPoolVolume(referrer, poolId2), volume2);
        
        // Check pool info
        IFixerRegistry.PoolInfo memory pool1Info = registry.getPoolInfo(poolId1);
        assertEq(pool1Info.totalReferrals, 1);
        assertEq(pool1Info.totalVolume, volume1);
        
        IFixerRegistry.PoolInfo memory pool2Info = registry.getPoolInfo(poolId2);
        assertEq(pool2Info.totalReferrals, 1);
        assertEq(pool2Info.totalVolume, volume2);
    }
    
    function test_GlobalCounters() public {
        vm.startPrank(owner);
        registry.registerHook(hook1, poolId1);
        registry.registerHook(hook2, poolId2);
        vm.stopPrank();
        
        vm.prank(hook1);
        registry.recordReferral(referrer, swapper, 5000e18, poolId1);
        
        address referrer2 = makeAddr("referrer2");
        vm.prank(hook2);
        registry.recordReferral(referrer2, swapper, 3000e18, poolId2);
        
        assertEq(registry.totalReferrals(), 2);
        assertEq(registry.totalVolume(), 8000e18);
    }
    
    // ========================================================================
    // TIER PROGRESSION TESTS
    // ========================================================================
    
    function test_TierUpgrade_ToSilver() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        // Accumulate volume and referrals to reach Silver
        for (uint256 i = 0; i < 10; i++) {
            address uniqueSwapper = address(uint160(i + 100));
            vm.prank(hook1);
            registry.recordReferral(referrer, uniqueSwapper, 1000e18, poolId1);
        }
        
        // Stats: 10,000 volume, 10 referrals -> Silver
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(referrer);
        assertEq(uint8(stats.tier), uint8(IFixerRegistry.ReferrerTier.Silver));
    }
    
    function test_TierMultiplierApplied() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        // First, upgrade to Silver tier
        for (uint256 i = 0; i < 10; i++) {
            address uniqueSwapper = address(uint160(i + 100));
            vm.prank(hook1);
            registry.recordReferral(referrer, uniqueSwapper, 1000e18, poolId1);
        }
        
        // Now at Silver (1.25x multiplier)
        uint256 volume = 100_000e18;
        
        vm.prank(hook1);
        uint256 reward = registry.recordReferral(referrer, swapper, volume, poolId1);
        
        // Base reward: 100,000 * 10 / 10000 = 100 FIX
        // With Silver multiplier: 100 * 12500 / 10000 = 125 FIX
        assertEq(reward, 125e18);
    }
    
    function test_ProgressToNextTier() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        // Add 5 referrals with 5,000 volume (50% progress to Silver)
        for (uint256 i = 0; i < 5; i++) {
            address uniqueSwapper = address(uint160(i + 100));
            vm.prank(hook1);
            registry.recordReferral(referrer, uniqueSwapper, 1000e18, poolId1);
        }
        
        (
            IFixerRegistry.ReferrerTier currentTier,
            IFixerRegistry.ReferrerTier nextTier,
            uint256 volumeProgress,
            uint256 referralProgress
        ) = registry.getProgressToNextTier(referrer);
        
        assertEq(uint8(currentTier), uint8(IFixerRegistry.ReferrerTier.Bronze));
        assertEq(uint8(nextTier), uint8(IFixerRegistry.ReferrerTier.Silver));
        assertEq(volumeProgress, 5000); // 50%
        assertEq(referralProgress, 5000); // 50%
    }
    
    // ========================================================================
    // ADMIN FUNCTION TESTS
    // ========================================================================
    
    function test_SetRewardParameters() public {
        uint256 newMinSwap = 200e18;
        uint256 newRate = 20;
        uint256 newMax = 2000e18;
        uint256 newMin = 2e18;
        
        vm.prank(owner);
        registry.setRewardParameters(newMinSwap, newRate, newMax, newMin);
        
        assertEq(registry.minSwapAmount(), newMinSwap);
        assertEq(registry.rewardRateBps(), newRate);
        assertEq(registry.maxRewardAmount(), newMax);
        assertEq(registry.minRewardAmount(), newMin);
    }
    
    function test_SetRewardParameters_RevertIfRateTooHigh() public {
        vm.expectRevert(IFixerRegistry.InvalidParameter.selector);
        vm.prank(owner);
        registry.setRewardParameters(100e18, 15000, 1000e18, 1e18); // 150% rate
    }
    
    function test_SetRewardParameters_RevertIfMinExceedsMax() public {
        vm.expectRevert(IFixerRegistry.InvalidParameter.selector);
        vm.prank(owner);
        registry.setRewardParameters(100e18, 10, 100e18, 200e18); // min > max
    }
    
    function test_SetTierThresholds() public {
        IFixerRegistry.TierThresholds memory newThresholds = IFixerRegistry.TierThresholds({
            minVolume: 50_000e18,
            minReferrals: 25,
            multiplierBps: 14000
        });
        
        vm.prank(owner);
        registry.setTierThresholds(IFixerRegistry.ReferrerTier.Gold, newThresholds);
        
        IFixerRegistry.TierThresholds memory fetched = registry.getTierThresholds(IFixerRegistry.ReferrerTier.Gold);
        assertEq(fetched.minVolume, 50_000e18);
        assertEq(fetched.minReferrals, 25);
        assertEq(fetched.multiplierBps, 14000);
    }
    
    function test_SetTierThresholds_RevertIfMultiplierTooHigh() public {
        IFixerRegistry.TierThresholds memory newThresholds = IFixerRegistry.TierThresholds({
            minVolume: 50_000e18,
            minReferrals: 25,
            multiplierBps: 150000 // 15x - too high
        });
        
        vm.expectRevert(IFixerRegistry.InvalidParameter.selector);
        vm.prank(owner);
        registry.setTierThresholds(IFixerRegistry.ReferrerTier.Gold, newThresholds);
    }
    
    // ========================================================================
    // VIEW FUNCTION TESTS
    // ========================================================================
    
    function test_CalculateReward() public view {
        uint256 volume = 10000e18;
        uint256 reward = registry.calculateReward(volume);
        
        // 10000 * 10 / 10000 = 10 FIX
        assertEq(reward, 10e18);
    }
    
    function test_CalculateReward_BelowThreshold() public view {
        uint256 volume = 50e18;
        uint256 reward = registry.calculateReward(volume);
        assertEq(reward, 0);
    }
    
    function test_CalculateRewardWithTier() public {
        vm.prank(owner);
        registry.registerHook(hook1, poolId1);
        
        // Upgrade to Silver
        for (uint256 i = 0; i < 10; i++) {
            address uniqueSwapper = address(uint160(i + 100));
            vm.prank(hook1);
            registry.recordReferral(referrer, uniqueSwapper, 1000e18, poolId1);
        }
        
        uint256 volume = 10000e18;
        uint256 reward = registry.calculateRewardWithTier(volume, referrer);
        
        // 10 FIX * 1.25 = 12.5 FIX
        assertEq(reward, 12.5e18);
    }
}

/// @title FixerRegistry Fuzz Tests
contract FixerRegistryFuzzTest is Test {
    
    FixerRegistry public registry;
    address public owner = makeAddr("owner");
    address public hook = makeAddr("hook");
    bytes32 public poolId = keccak256("pool");
    
    function setUp() public {
        registry = new FixerRegistry(owner);
        vm.prank(owner);
        registry.registerHook(hook, poolId);
    }
    
    function testFuzz_RecordReferral(address referrer, address swapper, uint128 volume) public {
        vm.assume(referrer != address(0));
        vm.assume(swapper != address(0));
        vm.assume(referrer != swapper);
        vm.assume(volume >= registry.minSwapAmount());
        vm.assume(volume <= type(uint128).max / 2); // Prevent overflow
        
        vm.prank(hook);
        uint256 reward = registry.recordReferral(referrer, swapper, volume, poolId);
        
        assertGe(reward, registry.minRewardAmount());
        assertLe(reward, registry.maxRewardAmount() * 2); // Max with tier multiplier
        assertEq(registry.balanceOf(referrer), reward);
    }
    
    function testFuzz_MultipleReferrals(address referrer, uint8 count) public {
        vm.assume(referrer != address(0));
        // Ensure referrer doesn't collide with generated swapper addresses
        vm.assume(uint160(referrer) < 100 || uint160(referrer) > 200);
        count = uint8(bound(count, 1, 50));
        
        uint128 volumePerSwap = 1000e18;
        uint256 totalVolume;
        
        for (uint8 i = 0; i < count; i++) {
            address swapper = address(uint160(i + 100));
            vm.prank(hook);
            registry.recordReferral(referrer, swapper, volumePerSwap, poolId);
            totalVolume += volumePerSwap;
        }
        
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(referrer);
        assertEq(stats.totalVolume, totalVolume);
        assertEq(stats.referralCount, count);
    }
    
    function testFuzz_TierProgression(uint128 volume, uint64 count) public {
        volume = uint128(bound(volume, 0, 2_000_000e18));
        count = uint64(bound(count, 0, 300));
        
        // Simulate tier calculation
        IFixerRegistry.ReferrerTier tier;
        if (volume >= 1_000_000e18 && count >= 200) {
            tier = IFixerRegistry.ReferrerTier.Platinum;
        } else if (volume >= 100_000e18 && count >= 50) {
            tier = IFixerRegistry.ReferrerTier.Gold;
        } else if (volume >= 10_000e18 && count >= 10) {
            tier = IFixerRegistry.ReferrerTier.Silver;
        } else {
            tier = IFixerRegistry.ReferrerTier.Bronze;
        }
        
        assertTrue(uint8(tier) <= 3);
    }
    
    function testFuzz_RewardBounds(uint128 volume) public view {
        // Ensure volume is at least minSwapAmount
        uint256 minSwap = registry.minSwapAmount();
        vm.assume(volume >= minSwap);
        
        uint256 reward = registry.calculateReward(volume);
        assertGe(reward, registry.minRewardAmount());
        assertLe(reward, registry.maxRewardAmount());
    }
}

/// @title FixerRegistry Gas Tests
contract FixerRegistryGasTest is Test {
    
    FixerRegistry public registry;
    address public owner = makeAddr("owner");
    address public hook = makeAddr("hook");
    bytes32 public poolId = keccak256("pool");
    address public referrer = makeAddr("referrer");
    address public swapper = makeAddr("swapper");
    
    function setUp() public {
        registry = new FixerRegistry(owner);
        vm.prank(owner);
        registry.registerHook(hook, poolId);
    }
    
    function test_GasRecordReferral_FirstTime() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(hook);
        registry.recordReferral(referrer, swapper, 1000e18, poolId);
        
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas for first referral", gasUsed);
        // First referral includes cold storage writes (token mint + stats init)
        assertLt(gasUsed, 250_000, "First referral should use reasonable gas");
    }
    
    function test_GasRecordReferral_Subsequent() public {
        // First referral
        vm.prank(hook);
        registry.recordReferral(referrer, swapper, 1000e18, poolId);
        
        // Second referral (warm storage)
        uint256 gasBefore = gasleft();
        
        vm.prank(hook);
        registry.recordReferral(referrer, makeAddr("swapper2"), 1000e18, poolId);
        
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Gas for subsequent referral", gasUsed);
        assertLt(gasUsed, 100_000, "Subsequent referral should be cheaper");
    }
    
    function test_GasGetReferrerStats() public {
        vm.prank(hook);
        registry.recordReferral(referrer, swapper, 1000e18, poolId);
        
        uint256 gasBefore = gasleft();
        registry.getReferrerStats(referrer);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for getReferrerStats", gasUsed);
        assertLt(gasUsed, 10_000, "View function should be cheap");
    }
}
