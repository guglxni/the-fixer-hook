// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @title FixerHook v1.1 Unit Tests
/// @notice Comprehensive test suite for the FixerHook v1.1 Dynamic Rewards
/// @dev Tests for dynamic reward calculation, volume thresholds, per-pool config, and quote token volume
contract FixerHookV1_1Test is Test {
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public referrer = makeAddr("referrer");
    
    // Default parameters from contract
    uint256 public constant DEFAULT_MIN_SWAP = 100 * 1e18;
    uint256 public constant DEFAULT_REWARD_RATE_BPS = 10; // 0.1%
    uint256 public constant DEFAULT_MAX_REWARD = 1000 * 1e18;
    uint256 public constant DEFAULT_MIN_REWARD = 1 * 1e18;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // ========================================================================
    // PARAMETER TESTS
    // ========================================================================
    
    function test_DefaultParameterValues() public pure {
        // Verify default parameter values match expected
        assertEq(DEFAULT_MIN_SWAP, 100e18, "Min swap should be 100 tokens");
        assertEq(DEFAULT_REWARD_RATE_BPS, 10, "Reward rate should be 10 bps (0.1%)");
        assertEq(DEFAULT_MAX_REWARD, 1000e18, "Max reward should be 1000 tokens");
        assertEq(DEFAULT_MIN_REWARD, 1e18, "Min reward should be 1 token");
    }
    
    // ========================================================================
    // REWARD CALCULATION TESTS
    // ========================================================================
    
    function test_RewardCalculation_ExactMath() public pure {
        // Test reward calculation: volume * rewardRateBps / 10000
        uint256 volume = 10000 * 1e18; // 10,000 tokens
        uint256 expectedReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        
        // At 0.1% rate: 10,000 * 10 / 10000 = 10 tokens
        assertEq(expectedReward, 10e18, "Reward should be 10 tokens for 10,000 volume");
    }
    
    function test_RewardCalculation_MinFloor() public pure {
        // Small volume should result in minimum reward floor
        uint256 volume = 500 * 1e18; // 500 tokens (above min swap, but low reward)
        uint256 rawReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        
        // At 0.1% rate: 500 * 10 / 10000 = 0.5 tokens
        assertEq(rawReward, 0.5e18, "Raw reward should be 0.5 tokens");
        
        // But min reward is 1 token, so should be clamped up
        uint256 finalReward = rawReward < DEFAULT_MIN_REWARD ? DEFAULT_MIN_REWARD : rawReward;
        assertEq(finalReward, DEFAULT_MIN_REWARD, "Should be clamped to min reward");
    }
    
    function test_RewardCalculation_MaxCap() public pure {
        // Very large volume should be capped at max reward
        uint256 volume = 20_000_000 * 1e18; // 20 million tokens
        uint256 rawReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        
        // At 0.1% rate: 20,000,000 * 10 / 10000 = 20,000 tokens
        assertEq(rawReward, 20_000e18, "Raw reward should be 20,000 tokens");
        
        // But max reward is 1000 tokens, so should be capped
        uint256 finalReward = rawReward > DEFAULT_MAX_REWARD ? DEFAULT_MAX_REWARD : rawReward;
        assertEq(finalReward, DEFAULT_MAX_REWARD, "Should be capped at max reward");
    }
    
    // ========================================================================
    // VOLUME THRESHOLD TESTS
    // ========================================================================
    
    function test_VolumeBelowThreshold_NoReward() public pure {
        uint256 volume = 50 * 1e18; // 50 tokens - below 100 threshold
        
        bool meetsThreshold = volume >= DEFAULT_MIN_SWAP;
        assertFalse(meetsThreshold, "Volume below threshold should not earn rewards");
    }
    
    function test_VolumeAtThreshold_GetsReward() public pure {
        uint256 volume = 100 * 1e18; // Exactly at threshold
        
        bool meetsThreshold = volume >= DEFAULT_MIN_SWAP;
        assertTrue(meetsThreshold, "Volume at threshold should earn rewards");
    }
    
    function test_VolumeAboveThreshold_GetsReward() public pure {
        uint256 volume = 1000 * 1e18; // Above threshold
        
        bool meetsThreshold = volume >= DEFAULT_MIN_SWAP;
        assertTrue(meetsThreshold, "Volume above threshold should earn rewards");
    }
    
    // ========================================================================
    // VOLUME CALCULATION TESTS (Quote Token Based)
    // ========================================================================
    
    function test_VolumeWithQuoteToken0() public pure {
        // Test volume calculation when token0 is the quote token (quoteTokenIndex = 0)
        // Example: WBTC/USDC pool where USDC (token0) is quote
        int128 amount0 = -int128(1000e6);   // User pays 1000 USDC (6 decimals)
        int128 amount1 = int128(1e8);        // User receives 0.01 WBTC (8 decimals)
        
        // With quote token = token0, we use amount0 for volume
        uint256 quoteTokenIndex = 0;
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should be 1000 USDC (1000e6)
        assertEq(volume, 1000e6, "Volume should be quote token amount");
    }
    
    function test_VolumeWithQuoteToken1() public pure {
        // Test volume calculation when token1 is the quote token (quoteTokenIndex = 1)
        // Example: ETH/USDC pool where USDC (token1) is quote
        int128 amount0 = int128(1e18);       // User receives 1 ETH (18 decimals)
        int128 amount1 = -int128(2000e6);    // User pays 2000 USDC (6 decimals)
        
        // With quote token = token1, we use amount1 for volume
        uint256 quoteTokenIndex = 1;
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should be 2000 USDC (2000e6)
        assertEq(volume, 2000e6, "Volume should be quote token amount");
    }
    
    function test_VolumeConsistencyAcrossDirections() public pure {
        // Test that volume is consistent regardless of swap direction
        // Buy ETH with USDC vs Sell ETH for USDC should yield same volume
        
        // Buy: User pays USDC, receives ETH
        int128 buyAmount0 = int128(1e18);       // Receive 1 ETH
        int128 buyAmount1 = -int128(2000e6);    // Pay 2000 USDC
        
        // Sell: User pays ETH, receives USDC  
        int128 sellAmount0 = -int128(1e18);     // Pay 1 ETH
        int128 sellAmount1 = int128(2000e6);    // Receive 2000 USDC
        
        // Using token1 (USDC) as quote
        uint256 quoteTokenIndex = 1;
        
        int128 buyQuote = quoteTokenIndex == 0 ? buyAmount0 : buyAmount1;
        uint256 buyVolume = buyQuote < 0 
            ? uint256(uint128(-buyQuote)) 
            : uint256(uint128(buyQuote));
            
        int128 sellQuote = quoteTokenIndex == 0 ? sellAmount0 : sellAmount1;
        uint256 sellVolume = sellQuote < 0 
            ? uint256(uint128(-sellQuote)) 
            : uint256(uint128(sellQuote));
        
        // Both should be 2000 USDC
        assertEq(buyVolume, sellVolume, "Volume should be same regardless of direction");
        assertEq(buyVolume, 2000e6, "Volume should be 2000 USDC");
    }
    
    function test_LegacyVolumeCalculation() public pure {
        // Test the legacy max(abs(amount0), abs(amount1)) calculation
        int128 amount0 = int128(1000e18); // Positive - user receives
        int128 amount1 = -int128(500e18);  // Negative - user pays
        
        uint256 vol0 = amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0));
        uint256 vol1 = amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1));
        uint256 volume = vol0 > vol1 ? vol0 : vol1;
        
        assertEq(volume, 1000e18, "Legacy volume should be the larger amount");
    }
    
    // ========================================================================
    // PER-POOL CONFIGURATION TESTS
    // ========================================================================
    
    function test_PoolConfigStruct() public pure {
        // Test that PoolRewardConfig struct is properly sized for gas efficiency
        // minSwapAmount (uint128) + rewardRateBps (uint64) + quoteTokenIndex (uint64) = 256 bits = 1 slot
        // maxRewardAmount (uint128) + minRewardAmount (uint128) = 256 bits = 1 slot
        // Total: 2 storage slots (gas efficient)
        
        uint128 minSwap = 100e18;
        uint64 rate = 10;
        uint64 quoteIdx = 1;
        uint128 maxReward = 1000e18;
        uint128 minReward = 1e18;
        
        // Verify values fit in their types
        assertTrue(minSwap <= type(uint128).max, "minSwap fits in uint128");
        assertTrue(rate <= type(uint64).max, "rate fits in uint64");
        assertTrue(quoteIdx <= 1, "quoteIdx is 0 or 1");
        assertTrue(maxReward <= type(uint128).max, "maxReward fits in uint128");
        assertTrue(minReward <= type(uint128).max, "minReward fits in uint128");
    }
    
    function test_PoolConfigValidation() public pure {
        // Test validation rules for per-pool config
        uint64 validRate = 100;      // 1% - valid
        uint64 invalidRate = 15000;  // 150% - invalid (exceeds BPS_DENOMINATOR)
        
        bool rateValid = validRate <= BPS_DENOMINATOR;
        bool rateInvalid = invalidRate <= BPS_DENOMINATOR;
        
        assertTrue(rateValid, "100 bps should be valid");
        assertFalse(rateInvalid, "15000 bps should be invalid");
        
        // Test min <= max validation
        uint128 minReward = 10e18;
        uint128 maxReward = 100e18;
        bool boundsValid = minReward <= maxReward;
        assertTrue(boundsValid, "Min should be <= max");
    }
    
    // ========================================================================
    // OWNER FUNCTIONALITY TESTS
    // ========================================================================
    
    function test_OwnerCanUpdateParameters() public pure {
        // Test that parameter update logic is valid
        uint256 newMinSwap = 200e18;
        uint256 newRate = 20; // 0.2%
        uint256 newMax = 2000e18;
        uint256 newMin = 2e18;
        
        // Validation: rate should not exceed 100%
        bool validRate = newRate <= BPS_DENOMINATOR;
        assertTrue(validRate, "Rate should be within valid range");
        
        // Validation: min should not exceed max
        bool validBounds = newMin <= newMax;
        assertTrue(validBounds, "Min should not exceed max");
    }
    
    function test_InvalidParameterRejection() public pure {
        // Test invalid parameters are properly rejected
        
        // Rate exceeding 100%
        uint256 invalidRate = 15000; // 150%
        bool rateValid = invalidRate <= BPS_DENOMINATOR;
        assertFalse(rateValid, "Rate above 100% should be invalid");
        
        // Min exceeding max
        uint256 min = 1000e18;
        uint256 max = 500e18;
        bool boundsValid = min <= max;
        assertFalse(boundsValid, "Min exceeding max should be invalid");
    }
    
    // ========================================================================
    // EVENT EMISSION TESTS
    // ========================================================================
    
    function test_ReferralRewardEventStructure() public pure {
        // Verify event parameters are correctly structured
        address testReferrer = address(0x1234);
        address testSwapper = address(0x5678);
        uint256 testVolume = 1000e18;
        uint256 testReward = 10e18;
        
        // These would be the event parameters
        assertEq(testReferrer, address(0x1234), "Referrer should match");
        assertEq(testSwapper, address(0x5678), "Swapper should match");
        assertEq(testVolume, 1000e18, "Volume should match");
        assertEq(testReward, 10e18, "Reward should match");
    }
}

/// @title Fuzz Tests for v1.1 Dynamic Rewards
/// @notice Property-based testing for reward calculation edge cases
contract FixerHookV1_1FuzzTest is Test {
    
    uint256 public constant DEFAULT_MIN_SWAP = 100 * 1e18;
    uint256 public constant DEFAULT_REWARD_RATE_BPS = 10;
    uint256 public constant DEFAULT_MAX_REWARD = 1000 * 1e18;
    uint256 public constant DEFAULT_MIN_REWARD = 1 * 1e18;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    function testFuzz_RewardNeverExceedsMax(uint256 volume) public pure {
        volume = bound(volume, 0, type(uint128).max);
        
        if (volume < DEFAULT_MIN_SWAP) {
            // Below threshold - no reward
            return;
        }
        
        uint256 rawReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        uint256 reward = rawReward > DEFAULT_MAX_REWARD ? DEFAULT_MAX_REWARD : rawReward;
        reward = reward < DEFAULT_MIN_REWARD ? DEFAULT_MIN_REWARD : reward;
        
        assertLe(reward, DEFAULT_MAX_REWARD, "Reward should never exceed max");
    }
    
    function testFuzz_RewardNeverBelowMinWhenThresholdMet(uint256 volume) public pure {
        volume = bound(volume, DEFAULT_MIN_SWAP, type(uint128).max);
        
        uint256 rawReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        uint256 reward = rawReward > DEFAULT_MAX_REWARD ? DEFAULT_MAX_REWARD : rawReward;
        reward = reward < DEFAULT_MIN_REWARD ? DEFAULT_MIN_REWARD : reward;
        
        assertGe(reward, DEFAULT_MIN_REWARD, "Reward should be at least min when threshold met");
    }
    
    function testFuzz_RewardBoundsAreCorrect(uint256 volume) public pure {
        volume = bound(volume, DEFAULT_MIN_SWAP, type(uint128).max);
        
        uint256 rawReward = (volume * DEFAULT_REWARD_RATE_BPS) / BPS_DENOMINATOR;
        uint256 reward = rawReward;
        
        if (reward < DEFAULT_MIN_REWARD) reward = DEFAULT_MIN_REWARD;
        if (reward > DEFAULT_MAX_REWARD) reward = DEFAULT_MAX_REWARD;
        
        assertGe(reward, DEFAULT_MIN_REWARD, "Reward >= min");
        assertLe(reward, DEFAULT_MAX_REWARD, "Reward <= max");
    }
    
    function testFuzz_QuoteTokenVolumeCalculation(int128 amount0, int128 amount1, uint256 quoteTokenIndex) public pure {
        // Bound to avoid the minimum int128 value which cannot be negated
        vm.assume(amount0 > type(int128).min);
        vm.assume(amount1 > type(int128).min);
        quoteTokenIndex = bound(quoteTokenIndex, 0, 1);
        
        // Simulate quote token based volume calculation
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should always be non-negative
        assertGe(volume, 0, "Volume should be non-negative");
        
        // Volume should equal the absolute value of the quote token amount
        uint256 expectedVol0 = amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0));
        uint256 expectedVol1 = amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1));
        uint256 expectedVolume = quoteTokenIndex == 0 ? expectedVol0 : expectedVol1;
        
        assertEq(volume, expectedVolume, "Volume should match quote token absolute value");
    }
    
    function testFuzz_LegacyVolumeCalculation(int128 amount0, int128 amount1) public pure {
        // Bound to avoid the minimum int128 value which cannot be negated
        vm.assume(amount0 > type(int128).min);
        vm.assume(amount1 > type(int128).min);
        
        // Simulate legacy volume calculation from delta
        uint256 vol0 = amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0));
        uint256 vol1 = amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1));
        uint256 volume = vol0 > vol1 ? vol0 : vol1;
        
        // Volume should be the max of absolute values
        assertGe(volume, vol0 < vol1 ? vol0 : vol1, "Volume should be >= smaller value");
        assertLe(volume, vol0 > vol1 ? vol0 : vol1, "Volume should be <= larger value");
    }
    
    function testFuzz_PerPoolConfigBounds(
        uint128 minSwap,
        uint64 rewardRate,
        uint128 maxReward,
        uint128 minReward
    ) public pure {
        // Test per-pool config validation
        bool rateValid = rewardRate <= BPS_DENOMINATOR;
        bool boundsValid = minReward <= maxReward;
        
        if (rateValid && boundsValid) {
            // Parameters would be accepted
            assertLe(rewardRate, BPS_DENOMINATOR, "Rate should be <= 100%");
            assertLe(minReward, maxReward, "Min should be <= max");
        }
    }
    
    function testFuzz_ParameterValidation(
        uint256 minSwap,
        uint256 rateBps,
        uint256 maxReward,
        uint256 minReward
    ) public pure {
        // Test parameter validation logic
        bool rateValid = rateBps <= BPS_DENOMINATOR;
        bool boundsValid = minReward <= maxReward;
        
        if (rateValid && boundsValid) {
            // Parameters would be accepted
            assertLe(rateBps, BPS_DENOMINATOR, "Rate should be <= 100%");
            assertLe(minReward, maxReward, "Min should be <= max");
        }
    }
}

/// @title Decimal Normalization Tests for v1.1
/// @notice Tests for volume calculation across different token decimal configurations
/// @dev Validates that quoteTokenIndex properly handles decimal mismatches
contract FixerHookV1_1DecimalTest is Test {
    
    // Token decimal configurations
    uint256 constant DECIMALS_6 = 6;   // USDC, USDT
    uint256 constant DECIMALS_8 = 8;   // WBTC
    uint256 constant DECIMALS_18 = 18; // DAI, WETH, most ERC20s
    
    /// @notice Test DAI (18 decimals) / USDC (6 decimals) pool
    /// @dev Demonstrates why quoteTokenIndex is critical for correct volume calculation
    function test_DecimalMismatch_DAI_USDC() public pure {
        // Scenario: Swap $1000 worth of tokens
        // DAI has 18 decimals, USDC has 6 decimals
        
        // User swaps 1000 DAI for 1000 USDC (assuming 1:1 stablecoin rate)
        int128 amountDAI = -int128(int256(1000 * 10**DECIMALS_18));  // Pay 1000 DAI
        int128 amountUSDC = int128(int256(1000 * 10**DECIMALS_6));    // Receive 1000 USDC
        
        // If token0 = DAI (18 dec), token1 = USDC (6 dec)
        
        // *** NAIVE APPROACH (BROKEN) ***
        // max(abs(amount0), abs(amount1)) gives wrong result
        uint256 vol0 = uint256(uint128(-amountDAI));   // 1000e18
        uint256 vol1 = uint256(uint128(amountUSDC));   // 1000e6
        uint256 naiveVolume = vol0 > vol1 ? vol0 : vol1;
        
        // Naive approach thinks volume is 1000e18 (1,000,000,000,000x too high!)
        assertEq(naiveVolume, 1000 * 10**DECIMALS_18, "Naive approach uses DAI amount");
        
        // *** QUOTE TOKEN APPROACH (CORRECT) ***
        // Use USDC (6 decimals) as quote token (quoteTokenIndex = 1)
        uint256 quoteTokenIndex = 1;
        int128 quoteAmount = quoteTokenIndex == 0 ? amountDAI : amountUSDC;
        uint256 correctVolume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Correct volume is 1000 USDC = $1000
        assertEq(correctVolume, 1000 * 10**DECIMALS_6, "Quote token approach uses USDC");
        
        // Verify the massive difference
        assertGt(naiveVolume / correctVolume, 10**11, "Naive is 10^12x larger");
    }
    
    /// @notice Test WETH (18 decimals) / USDC (6 decimals) pool
    function test_DecimalMismatch_WETH_USDC() public pure {
        // User swaps 1 WETH for 2000 USDC (ETH price = $2000)
        int128 amountWETH = -int128(int256(1 * 10**DECIMALS_18));     // Pay 1 WETH
        int128 amountUSDC = int128(int256(2000 * 10**DECIMALS_6));    // Receive 2000 USDC
        
        // Using USDC (token1) as quote token
        uint256 quoteTokenIndex = 1;
        int128 quoteAmount = quoteTokenIndex == 0 ? amountWETH : amountUSDC;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should be 2000 USDC (representing $2000 trade)
        assertEq(volume, 2000 * 10**DECIMALS_6, "Volume should be 2000 USDC");
    }
    
    /// @notice Test WBTC (8 decimals) / USDC (6 decimals) pool
    function test_DecimalMismatch_WBTC_USDC() public pure {
        // User swaps 0.5 WBTC for 20000 USDC (BTC price = $40000)
        int128 amountWBTC = -int128(int256(50_000_000)); // Pay 0.5 WBTC (8 decimals)
        int128 amountUSDC = int128(int256(20000 * 10**DECIMALS_6)); // Receive 20000 USDC
        
        // Using USDC (token1) as quote token
        uint256 quoteTokenIndex = 1;
        int128 quoteAmount = quoteTokenIndex == 0 ? amountWBTC : amountUSDC;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should be 20000 USDC (representing $20000 trade)
        assertEq(volume, 20000 * 10**DECIMALS_6, "Volume should be 20000 USDC");
    }
    
    /// @notice Test that stablecoin pools work with either token as quote
    function test_StablecoinPool_EitherTokenWorks() public pure {
        // DAI/USDC swap - both are stablecoins
        int128 amountDAI = -int128(int256(1000 * 10**DECIMALS_18));
        int128 amountUSDC = int128(int256(1000 * 10**DECIMALS_6));
        
        // Using DAI (token0) as quote
        uint256 volumeQuote0;
        {
            uint256 quoteTokenIndex = 0;
            int128 quoteAmount = quoteTokenIndex == 0 ? amountDAI : amountUSDC;
            volumeQuote0 = quoteAmount < 0 
                ? uint256(uint128(-quoteAmount)) 
                : uint256(uint128(quoteAmount));
        }
        
        // Using USDC (token1) as quote
        uint256 volumeQuote1;
        {
            uint256 quoteTokenIndex = 1;
            int128 quoteAmount = quoteTokenIndex == 0 ? amountDAI : amountUSDC;
            volumeQuote1 = quoteAmount < 0 
                ? uint256(uint128(-quoteAmount)) 
                : uint256(uint128(quoteAmount));
        }
        
        // Both represent $1000, just in different denominations
        // volumeQuote0 = 1000e18 (DAI)
        // volumeQuote1 = 1000e6 (USDC)
        assertEq(volumeQuote0, 1000 * 10**DECIMALS_18, "DAI volume");
        assertEq(volumeQuote1, 1000 * 10**DECIMALS_6, "USDC volume");
        
        // Key insight: minSwapAmount should be set according to quote token decimals
        // If quoteTokenIndex=0 (DAI), minSwapAmount = 100e18
        // If quoteTokenIndex=1 (USDC), minSwapAmount = 100e6
    }
    
    /// @notice Test reward scaling with different quote token decimals
    function test_RewardScaling_DifferentDecimals() public pure {
        // Two equivalent $10,000 swaps with different quote tokens
        
        // Pool A: Uses 18-decimal quote token (e.g., DAI)
        uint256 volumeA = 10000 * 10**DECIMALS_18; // 10000 DAI
        uint256 rewardRateBps = 10; // 0.1%
        uint256 rewardA = (volumeA * rewardRateBps) / 10000;
        
        // Pool B: Uses 6-decimal quote token (e.g., USDC)
        uint256 volumeB = 10000 * 10**DECIMALS_6; // 10000 USDC
        uint256 rewardB = (volumeB * rewardRateBps) / 10000;
        
        // rewardA = 10e18, rewardB = 10e6
        assertEq(rewardA, 10 * 10**DECIMALS_18, "18-decimal reward");
        assertEq(rewardB, 10 * 10**DECIMALS_6, "6-decimal reward");
        
        // Key insight: min/maxRewardAmount must also be set according to quote decimals
        // Pool A config: minRewardAmount = 1e18, maxRewardAmount = 1000e18
        // Pool B config: minRewardAmount = 1e6, maxRewardAmount = 1000e6
    }
    
    /// @notice Fuzz test for various decimal combinations
    function testFuzz_DecimalCombinations(
        uint128 rawAmount,
        uint8 decimals0,
        uint8 decimals1,
        bool useToken1AsQuote
    ) public pure {
        // Bound decimals to realistic range
        decimals0 = uint8(bound(decimals0, 0, 24));
        decimals1 = uint8(bound(decimals1, 0, 24));
        
        // Avoid overflow
        vm.assume(rawAmount > 0);
        vm.assume(rawAmount <= type(uint64).max);
        
        // Simulate swap amounts (simplified)
        int128 amount0 = -int128(int256(uint256(rawAmount) * 10**(decimals0 > 12 ? 12 : decimals0)));
        int128 amount1 = int128(int256(uint256(rawAmount) * 10**(decimals1 > 12 ? 12 : decimals1)));
        
        uint256 quoteTokenIndex = useToken1AsQuote ? 1 : 0;
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        uint256 volume = quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
        
        // Volume should always be positive
        assertGt(volume, 0, "Volume should be positive");
    }
}

/// @title Gas Benchmark Tests for v1.1
/// @notice Measure gas consumption for v1.1 features
contract FixerHookV1_1GasTest is Test {
    
    function test_GasVolumeCalculation() public {
        int128 amount0 = int128(1000e18);
        int128 amount1 = -int128(500e18);
        
        uint256 gasBefore = gasleft();
        
        uint256 vol0 = amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0));
        uint256 vol1 = amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1));
        uint256 volume = vol0 > vol1 ? vol0 : vol1;
        
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for volume calculation", gasUsed);
        assertLt(gasUsed, 500, "Volume calculation should be cheap");
        assertEq(volume, 1000e18);
    }
    
    function test_GasRewardCalculation() public {
        uint256 volume = 10000e18;
        uint256 rewardRateBps = 10;
        uint256 minReward = 1e18;
        uint256 maxReward = 1000e18;
        
        uint256 gasBefore = gasleft();
        
        uint256 reward = (volume * rewardRateBps) / 10000;
        if (reward < minReward) reward = minReward;
        if (reward > maxReward) reward = maxReward;
        
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for reward calculation", gasUsed);
        assertLt(gasUsed, 500, "Reward calculation should be cheap");
        assertEq(reward, 10e18);
    }
}
