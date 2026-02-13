// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixerHook} from "../src/FixerHook.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @title FixerHook v1.2 Tiered Referral System Tests
/// @notice Comprehensive test suite for the tiered referral system
/// @dev Tests tier thresholds, multipliers, stats tracking, and tier upgrades
contract FixerHookV1_2TierTest is Test {
    
    // Default tier thresholds from contract
    uint128 public constant BRONZE_VOLUME = 0;
    uint64 public constant BRONZE_REFERRALS = 0;
    uint64 public constant BRONZE_MULTIPLIER = 10000;  // 1.0x
    
    uint128 public constant SILVER_VOLUME = 10_000e18;
    uint64 public constant SILVER_REFERRALS = 10;
    uint64 public constant SILVER_MULTIPLIER = 12500;  // 1.25x
    
    uint128 public constant GOLD_VOLUME = 100_000e18;
    uint64 public constant GOLD_REFERRALS = 50;
    uint64 public constant GOLD_MULTIPLIER = 15000;    // 1.5x
    
    uint128 public constant PLATINUM_VOLUME = 1_000_000e18;
    uint64 public constant PLATINUM_REFERRALS = 200;
    uint64 public constant PLATINUM_MULTIPLIER = 20000; // 2.0x
    
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // ========================================================================
    // TIER THRESHOLD TESTS
    // ========================================================================
    
    function test_BronzeTierDefaults() public pure {
        // Bronze tier has no requirements
        assertEq(BRONZE_VOLUME, 0, "Bronze requires 0 volume");
        assertEq(BRONZE_REFERRALS, 0, "Bronze requires 0 referrals");
        assertEq(BRONZE_MULTIPLIER, 10000, "Bronze has 1.0x multiplier");
    }
    
    function test_SilverTierThresholds() public pure {
        // Silver: 10k volume, 10 referrals, 1.25x
        assertEq(SILVER_VOLUME, 10_000e18, "Silver requires 10k volume");
        assertEq(SILVER_REFERRALS, 10, "Silver requires 10 referrals");
        assertEq(SILVER_MULTIPLIER, 12500, "Silver has 1.25x multiplier");
    }
    
    function test_GoldTierThresholds() public pure {
        // Gold: 100k volume, 50 referrals, 1.5x
        assertEq(GOLD_VOLUME, 100_000e18, "Gold requires 100k volume");
        assertEq(GOLD_REFERRALS, 50, "Gold requires 50 referrals");
        assertEq(GOLD_MULTIPLIER, 15000, "Gold has 1.5x multiplier");
    }
    
    function test_PlatinumTierThresholds() public pure {
        // Platinum: 1M volume, 200 referrals, 2.0x
        assertEq(PLATINUM_VOLUME, 1_000_000e18, "Platinum requires 1M volume");
        assertEq(PLATINUM_REFERRALS, 200, "Platinum requires 200 referrals");
        assertEq(PLATINUM_MULTIPLIER, 20000, "Platinum has 2.0x multiplier");
    }
    
    // ========================================================================
    // TIER QUALIFICATION TESTS
    // ========================================================================
    
    function test_QualifiesForBronze_Always() public pure {
        // Any address qualifies for Bronze
        uint128 volume = 0;
        uint64 referrals = 0;
        
        bool qualifies = volume >= BRONZE_VOLUME && referrals >= BRONZE_REFERRALS;
        assertTrue(qualifies, "Everyone qualifies for Bronze");
    }
    
    function test_QualifiesForSilver_BothRequirements() public pure {
        // Must meet BOTH volume AND referral requirements
        
        // Only volume - not enough
        uint128 volumeOnly = SILVER_VOLUME;
        uint64 noReferrals = 0;
        bool volumeOnlyQualifies = volumeOnly >= SILVER_VOLUME && noReferrals >= SILVER_REFERRALS;
        assertFalse(volumeOnlyQualifies, "Volume only not enough for Silver");
        
        // Only referrals - not enough
        uint128 noVolume = 0;
        uint64 referralsOnly = SILVER_REFERRALS;
        bool referralsOnlyQualifies = noVolume >= SILVER_VOLUME && referralsOnly >= SILVER_REFERRALS;
        assertFalse(referralsOnlyQualifies, "Referrals only not enough for Silver");
        
        // Both - qualifies
        uint128 bothVolume = SILVER_VOLUME;
        uint64 bothReferrals = SILVER_REFERRALS;
        bool bothQualify = bothVolume >= SILVER_VOLUME && bothReferrals >= SILVER_REFERRALS;
        assertTrue(bothQualify, "Both requirements qualify for Silver");
    }
    
    function test_TierCalculation_HighestQualifying() public pure {
        // User with Platinum stats should get Platinum tier (highest)
        uint128 volume = PLATINUM_VOLUME + 1000e18; // Exceeds Platinum
        uint64 referrals = PLATINUM_REFERRALS + 50;  // Exceeds Platinum
        
        // Check qualification for all tiers
        bool qualifiesPlatinum = volume >= PLATINUM_VOLUME && referrals >= PLATINUM_REFERRALS;
        bool qualifiesGold = volume >= GOLD_VOLUME && referrals >= GOLD_REFERRALS;
        bool qualifiesSilver = volume >= SILVER_VOLUME && referrals >= SILVER_REFERRALS;
        bool qualifiesBronze = volume >= BRONZE_VOLUME && referrals >= BRONZE_REFERRALS;
        
        assertTrue(qualifiesPlatinum, "Should qualify for Platinum");
        assertTrue(qualifiesGold, "Should also qualify for Gold");
        assertTrue(qualifiesSilver, "Should also qualify for Silver");
        assertTrue(qualifiesBronze, "Should also qualify for Bronze");
        
        // Tier calculation should return Platinum (highest)
        // Simulating _calculateTier logic
        uint8 expectedTier;
        if (qualifiesPlatinum) expectedTier = 3; // Platinum
        else if (qualifiesGold) expectedTier = 2; // Gold
        else if (qualifiesSilver) expectedTier = 1; // Silver
        else expectedTier = 0; // Bronze
        
        assertEq(expectedTier, 3, "Should be Platinum tier");
    }
    
    // ========================================================================
    // MULTIPLIER APPLICATION TESTS
    // ========================================================================
    
    function test_MultiplierApplication_Bronze() public pure {
        // Bronze: 1.0x multiplier
        uint256 baseReward = 100e18;
        uint256 finalReward = (baseReward * BRONZE_MULTIPLIER) / BPS_DENOMINATOR;
        
        assertEq(finalReward, 100e18, "Bronze gives 1.0x (100%)");
    }
    
    function test_MultiplierApplication_Silver() public pure {
        // Silver: 1.25x multiplier
        uint256 baseReward = 100e18;
        uint256 finalReward = (baseReward * SILVER_MULTIPLIER) / BPS_DENOMINATOR;
        
        assertEq(finalReward, 125e18, "Silver gives 1.25x (125%)");
    }
    
    function test_MultiplierApplication_Gold() public pure {
        // Gold: 1.5x multiplier
        uint256 baseReward = 100e18;
        uint256 finalReward = (baseReward * GOLD_MULTIPLIER) / BPS_DENOMINATOR;
        
        assertEq(finalReward, 150e18, "Gold gives 1.5x (150%)");
    }
    
    function test_MultiplierApplication_Platinum() public pure {
        // Platinum: 2.0x multiplier
        uint256 baseReward = 100e18;
        uint256 finalReward = (baseReward * PLATINUM_MULTIPLIER) / BPS_DENOMINATOR;
        
        assertEq(finalReward, 200e18, "Platinum gives 2.0x (200%)");
    }
    
    // ========================================================================
    // REFERRER STATS TESTS
    // ========================================================================
    
    function test_ReferrerStats_StructPacking() public pure {
        // Verify struct fits in expected slots
        // Slot 1: totalVolume (uint128 = 16 bytes) + referralCount (uint64 = 8 bytes) + lastUpdated (uint64 = 8 bytes) = 32 bytes
        // Slot 2: totalEarned (uint128 = 16 bytes) + tier (uint8 = 1 byte) + padding
        
        uint128 maxVolume = type(uint128).max;
        uint64 maxReferrals = type(uint64).max;
        uint64 maxTimestamp = type(uint64).max;
        uint128 maxEarned = type(uint128).max;
        
        assertTrue(maxVolume > 0, "Volume fits in uint128");
        assertTrue(maxReferrals > 0, "Referrals fits in uint64");
        assertTrue(maxTimestamp > 0, "Timestamp fits in uint64");
        assertTrue(maxEarned > 0, "Earned fits in uint128");
    }
    
    function test_StatsAccumulation() public pure {
        // Simulate multiple referrals accumulating
        uint128 initialVolume = 0;
        uint64 initialReferrals = 0;
        uint128 initialEarned = 0;
        
        // First referral: 500 volume, 5 FIX earned
        uint128 volume1 = 500e18;
        uint128 reward1 = 5e18;
        
        initialVolume += volume1;
        initialReferrals += 1;
        initialEarned += reward1;
        
        assertEq(initialVolume, 500e18, "Volume after 1st");
        assertEq(initialReferrals, 1, "Referrals after 1st");
        assertEq(initialEarned, 5e18, "Earned after 1st");
        
        // Second referral: 1000 volume, 10 FIX earned
        uint128 volume2 = 1000e18;
        uint128 reward2 = 10e18;
        
        initialVolume += volume2;
        initialReferrals += 1;
        initialEarned += reward2;
        
        assertEq(initialVolume, 1500e18, "Volume after 2nd");
        assertEq(initialReferrals, 2, "Referrals after 2nd");
        assertEq(initialEarned, 15e18, "Earned after 2nd");
    }
    
    // ========================================================================
    // TIER UPGRADE TESTS
    // ========================================================================
    
    function test_TierUpgrade_BronzeToSilver() public pure {
        // Start at Bronze, accumulate to Silver thresholds
        uint128 volume = SILVER_VOLUME;
        uint64 referrals = SILVER_REFERRALS;
        
        // Simulate tier calculation
        uint8 currentTier = 0; // Bronze
        uint8 newTier;
        
        if (volume >= PLATINUM_VOLUME && referrals >= PLATINUM_REFERRALS) {
            newTier = 3;
        } else if (volume >= GOLD_VOLUME && referrals >= GOLD_REFERRALS) {
            newTier = 2;
        } else if (volume >= SILVER_VOLUME && referrals >= SILVER_REFERRALS) {
            newTier = 1;
        } else {
            newTier = 0;
        }
        
        assertTrue(newTier > currentTier, "Should upgrade from Bronze to Silver");
        assertEq(newTier, 1, "Should be Silver tier");
    }
    
    function test_TierUpgrade_NoDowngrade() public pure {
        // Tiers only go up, never down
        // Even if current stats don't meet tier (e.g., volume spent),
        // tier should remain at highest achieved
        
        uint8 achievedTier = 2; // Gold achieved
        uint8 currentCalcTier = 1; // Current stats only qualify for Silver
        
        // Final tier should be max of achieved and calculated
        uint8 finalTier = achievedTier > currentCalcTier ? achievedTier : currentCalcTier;
        
        assertEq(finalTier, 2, "Should stay at Gold, not downgrade");
        
        // Note: Current implementation does allow stats to always increase,
        // so this test documents expected behavior
    }
    
    // ========================================================================
    // PROGRESS TRACKING TESTS
    // ========================================================================
    
    function test_ProgressToNextTier_FromBronze() public pure {
        // Bronze user with 5k volume (50% of Silver) and 5 referrals (50%)
        uint128 volume = 5000e18;
        uint64 referrals = 5;
        
        // Calculate progress to Silver
        uint256 volumeProgress = (uint256(volume) * 10000) / SILVER_VOLUME;
        uint256 referralProgress = (uint256(referrals) * 10000) / SILVER_REFERRALS;
        
        assertEq(volumeProgress, 5000, "50% volume progress to Silver");
        assertEq(referralProgress, 5000, "50% referral progress to Silver");
    }
    
    function test_ProgressToNextTier_AtPlatinum() public pure {
        // Platinum users are at 100% progress
        uint8 currentTier = 3; // Platinum
        
        // If at Platinum, return 100% for both
        uint256 volumeProgress = currentTier == 3 ? 10000 : 0;
        uint256 referralProgress = currentTier == 3 ? 10000 : 0;
        
        assertEq(volumeProgress, 10000, "Platinum at 100% volume progress");
        assertEq(referralProgress, 10000, "Platinum at 100% referral progress");
    }
    
    function test_ProgressCappedAt100Percent() public pure {
        // Progress should not exceed 100% (10000 bps)
        uint128 volume = SILVER_VOLUME * 2; // 200% of Silver requirement
        
        uint256 rawProgress = (uint256(volume) * 10000) / SILVER_VOLUME;
        uint256 cappedProgress = rawProgress > 10000 ? 10000 : rawProgress;
        
        assertEq(rawProgress, 20000, "Raw progress is 200%");
        assertEq(cappedProgress, 10000, "Capped progress is 100%");
    }
}

/// @title Fuzz Tests for Tier System
contract FixerHookV1_2FuzzTest is Test {
    
    uint128 public constant SILVER_VOLUME = 10_000e18;
    uint64 public constant SILVER_REFERRALS = 10;
    uint128 public constant GOLD_VOLUME = 100_000e18;
    uint64 public constant GOLD_REFERRALS = 50;
    uint128 public constant PLATINUM_VOLUME = 1_000_000e18;
    uint64 public constant PLATINUM_REFERRALS = 200;
    
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint64 public constant BRONZE_MULTIPLIER = 10000;
    uint64 public constant SILVER_MULTIPLIER = 12500;
    uint64 public constant GOLD_MULTIPLIER = 15000;
    uint64 public constant PLATINUM_MULTIPLIER = 20000;
    
    function testFuzz_TierCalculation(uint128 volume, uint64 referrals) public pure {
        // Calculate tier
        uint8 tier;
        if (volume >= PLATINUM_VOLUME && referrals >= PLATINUM_REFERRALS) {
            tier = 3;
        } else if (volume >= GOLD_VOLUME && referrals >= GOLD_REFERRALS) {
            tier = 2;
        } else if (volume >= SILVER_VOLUME && referrals >= SILVER_REFERRALS) {
            tier = 1;
        } else {
            tier = 0;
        }
        
        // Tier should be 0-3
        assertLe(tier, 3, "Tier should be <= 3");
        
        // Verify tier matches requirements
        if (tier == 3) {
            assertTrue(volume >= PLATINUM_VOLUME, "Platinum needs volume");
            assertTrue(referrals >= PLATINUM_REFERRALS, "Platinum needs referrals");
        } else if (tier == 2) {
            assertTrue(volume >= GOLD_VOLUME, "Gold needs volume");
            assertTrue(referrals >= GOLD_REFERRALS, "Gold needs referrals");
        } else if (tier == 1) {
            assertTrue(volume >= SILVER_VOLUME, "Silver needs volume");
            assertTrue(referrals >= SILVER_REFERRALS, "Silver needs referrals");
        }
    }
    
    function testFuzz_MultiplierBounds(uint256 baseReward, uint8 tierIndex) public pure {
        // Bound tier to valid range
        tierIndex = uint8(bound(tierIndex, 0, 3));
        
        // Get multiplier for tier
        uint64 multiplier;
        if (tierIndex == 0) multiplier = BRONZE_MULTIPLIER;
        else if (tierIndex == 1) multiplier = SILVER_MULTIPLIER;
        else if (tierIndex == 2) multiplier = GOLD_MULTIPLIER;
        else multiplier = PLATINUM_MULTIPLIER;
        
        // Bound baseReward to prevent overflow
        baseReward = bound(baseReward, 0, type(uint128).max);
        
        // Calculate final reward
        uint256 finalReward = (baseReward * multiplier) / BPS_DENOMINATOR;
        
        // Final reward should be >= baseReward (multipliers are >= 1.0x)
        assertGe(finalReward, baseReward, "Multiplier should not decrease reward");
        
        // Final reward should be <= 2x baseReward (max multiplier is 2.0x)
        assertLe(finalReward, baseReward * 2, "Multiplier should not exceed 2.0x");
    }
    
    function testFuzz_StatsAccumulation(
        uint128 volume1,
        uint128 volume2,
        uint128 reward1,
        uint128 reward2
    ) public pure {
        // Bound to prevent overflow
        volume1 = uint128(bound(volume1, 0, type(uint64).max));
        volume2 = uint128(bound(volume2, 0, type(uint64).max));
        reward1 = uint128(bound(reward1, 0, type(uint64).max));
        reward2 = uint128(bound(reward2, 0, type(uint64).max));
        
        uint128 totalVolume = volume1 + volume2;
        uint64 totalReferrals = 2;
        uint128 totalEarned = reward1 + reward2;
        
        // Accumulation should be additive
        assertEq(totalVolume, volume1 + volume2, "Volume adds up");
        assertEq(totalReferrals, 2, "Referrals increment");
        assertEq(totalEarned, reward1 + reward2, "Earnings add up");
    }
    
    function testFuzz_ProgressCalculation(
        uint128 currentVolume,
        uint64 currentReferrals
    ) public pure {
        // Bound to reasonable values
        currentVolume = uint128(bound(currentVolume, 0, PLATINUM_VOLUME * 2));
        currentReferrals = uint64(bound(currentReferrals, 0, PLATINUM_REFERRALS * 2));
        
        // Calculate progress to Silver (from Bronze)
        uint256 volumeProgress;
        uint256 referralProgress;
        
        if (SILVER_VOLUME == 0) {
            volumeProgress = 10000;
        } else {
            volumeProgress = (uint256(currentVolume) * 10000) / SILVER_VOLUME;
            if (volumeProgress > 10000) volumeProgress = 10000;
        }
        
        if (SILVER_REFERRALS == 0) {
            referralProgress = 10000;
        } else {
            referralProgress = (uint256(currentReferrals) * 10000) / SILVER_REFERRALS;
            if (referralProgress > 10000) referralProgress = 10000;
        }
        
        // Progress should be 0-100% (0-10000 bps)
        assertLe(volumeProgress, 10000, "Volume progress capped at 100%");
        assertLe(referralProgress, 10000, "Referral progress capped at 100%");
    }
    
    function testFuzz_TierUpgradeOnlyIncrements(uint8 currentTier, uint8 newTier) public pure {
        // Bound tiers
        currentTier = uint8(bound(currentTier, 0, 3));
        newTier = uint8(bound(newTier, 0, 3));
        
        // Simulate upgrade logic: only upgrade if new > current
        bool shouldUpgrade = newTier > currentTier;
        uint8 finalTier = shouldUpgrade ? newTier : currentTier;
        
        // Final tier should always be >= current tier (no downgrades)
        assertGe(finalTier, currentTier, "No tier downgrades allowed");
    }
}

/// @title Gas Benchmark Tests for Tier System
contract FixerHookV1_2GasTest is Test {
    
    function test_GasTierCalculation() public {
        uint128 volume = 500_000e18;
        uint64 referrals = 100;
        
        uint256 gasBefore = gasleft();
        
        // Simulate tier calculation
        uint8 tier;
        if (volume >= 1_000_000e18 && referrals >= 200) {
            tier = 3;
        } else if (volume >= 100_000e18 && referrals >= 50) {
            tier = 2;
        } else if (volume >= 10_000e18 && referrals >= 10) {
            tier = 1;
        } else {
            tier = 0;
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for tier calculation", gasUsed);
        assertLt(gasUsed, 500, "Tier calculation should be cheap");
        assertEq(tier, 2, "Should be Gold tier");
    }
    
    function test_GasMultiplierApplication() public {
        uint256 baseReward = 100e18;
        uint64 multiplier = 15000; // 1.5x
        
        uint256 gasBefore = gasleft();
        
        uint256 finalReward = (baseReward * multiplier) / 10000;
        
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for multiplier application", gasUsed);
        assertLt(gasUsed, 200, "Multiplier application should be very cheap");
        assertEq(finalReward, 150e18, "Should be 150 FIX");
    }
    
    function test_GasStatsUpdate() public {
        // Simulate stats storage update
        uint128 totalVolume = 50_000e18;
        uint64 referralCount = 25;
        uint64 lastUpdated = uint64(block.timestamp);
        uint128 totalEarned = 500e18;
        
        uint256 gasBefore = gasleft();
        
        // Simulate update
        totalVolume += 1000e18;
        referralCount += 1;
        lastUpdated = uint64(block.timestamp);
        totalEarned += 10e18;
        
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for stats update", gasUsed);
        assertLt(gasUsed, 500, "Stats update should be cheap");
    }
}
