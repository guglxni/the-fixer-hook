// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {ProtocolFeeConstants} from "../src/types/AgentTypes.sol";

/// @title FixerRegistryUpgradeTest
/// @notice Tests for UUPS proxy deployment, initialization, upgrade, and state preservation
contract FixerRegistryUpgradeTest is Test {
    // ========================================================================
    // STATE
    // ========================================================================

    FixerRegistryUpgradeable public implementation;
    ERC1967Proxy public proxy;
    FixerRegistryUpgradeable public registry; // proxy cast

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public hookAddr = makeAddr("hook");

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public {
        // Deploy implementation
        implementation = new FixerRegistryUpgradeable();

        // Deploy proxy with initialize
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_initialization_owner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_initialization_token() public view {
        assertEq(registry.name(), "Fixer Token");
        assertEq(registry.symbol(), "FIX");
        assertEq(registry.decimals(), 18);
    }

    function test_initialization_version() public view {
        assertEq(registry.VERSION(), 2_003_000);
    }

    function test_initialization_protocolFee() public view {
        (uint64 feeBps, uint64 maxFeeBps) = registry.getProtocolFeeConfig();
        assertEq(feeBps, 500);      // 5%
        assertEq(maxFeeBps, 1000);  // 10% max
    }

    function test_initialization_emergencyState() public view {
        (
            bool pausedReferrals,
            bool pausedAgents,
            bool pausedRewards,
            ,
            ,
            ,
            uint256 circuitBreakerThreshold,
            ,
            address sc,
            address gov
        ) = registry.getEmergencyState();

        assertFalse(pausedReferrals);
        assertFalse(pausedAgents);
        assertFalse(pausedRewards);
        assertEq(circuitBreakerThreshold, 1_000_000e18);
        assertEq(sc, securityCouncil);
        assertEq(gov, governance);
    }

    function test_initialization_tierThresholds() public view {
        FixerRegistryStorage.TierThresholds memory bronze =
            registry.getTierThresholds(FixerRegistryStorage.ReferrerTier.Bronze);
        assertEq(bronze.minVolume, 0);
        assertEq(bronze.minReferrals, 0);
        assertEq(bronze.multiplierBps, 10000); // 1.0x

        FixerRegistryStorage.TierThresholds memory platinum =
            registry.getTierThresholds(FixerRegistryStorage.ReferrerTier.Platinum);
        assertEq(platinum.minVolume, 1_000_000e18);
        assertEq(platinum.minReferrals, 200);
        assertEq(platinum.multiplierBps, 20000); // 2.0x
    }

    function test_cannotReinitialize() public {
        vm.expectRevert();
        registry.initialize(user1, user1, user1);
    }

    function test_implementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(user1, user1, user1);
    }

    // ========================================================================
    // REFERRAL TESTS (via proxy)
    // ========================================================================

    function test_recordReferral_basic() public {
        bytes32 poolId = keccak256("pool1");

        // Register hook
        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Record referral (volume = 1000 tokens)
        vm.prank(hookAddr);
        uint256 reward = registry.recordReferral(user1, user2, 1000e18, poolId);

        // reward = 1000e18 * 10/10000 * 10000/10000 * 9500/10000
        // = 1e18 * 0.95 = 0.95e18
        // But minRewardAmount is 1e18, so base goes up to 1e18, then 5% fee:
        // gross = 1e18 * 10000 / 10000 = 1e18
        // net = 1e18 - 0.05e18 = 0.95e18
        assertEq(reward, 0.95e18);
        assertEq(registry.balanceOf(user1), 0.95e18);
    }

    function test_recordReferral_belowMinimum() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Volume below minimum (50 < 100)
        vm.prank(hookAddr);
        uint256 reward = registry.recordReferral(user1, user2, 50e18, poolId);

        assertEq(reward, 0);
    }

    function test_recordReferral_selfReferralReverts() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        vm.prank(hookAddr);
        vm.expectRevert(FixerRegistryUpgradeable.SelfReferral.selector);
        registry.recordReferral(user1, user1, 1000e18, poolId);
    }

    function test_recordReferral_unauthorizedHookReverts() public {
        vm.prank(user1);
        vm.expectRevert(FixerRegistryUpgradeable.UnauthorizedHook.selector);
        registry.recordReferral(user1, user2, 1000e18, keccak256("pool1"));
    }

    function test_recordReferral_updatesStats() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);

        FixerRegistryStorage.ReferrerStats memory stats = registry.getReferrerStats(user1);
        assertEq(stats.totalVolume, 1000e18);
        assertEq(stats.referralCount, 1);
        assertGt(stats.lastUpdated, 0);
        assertGt(stats.totalEarned, 0);
    }

    function test_recordReferral_globalStats() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);

        (uint64 hookCount, uint64 totalRefs, uint128 totalVol) = registry.getGlobalStats();
        assertEq(hookCount, 1);
        assertEq(totalRefs, 1);
        assertEq(totalVol, 1000e18);
    }

    // ========================================================================
    // PROTOCOL FEE TESTS
    // ========================================================================

    function test_protocolFee_accumulates() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);

        uint256 fees = registry.getAccumulatedFees();
        assertGt(fees, 0);
    }

    function test_protocolFee_distribution() public {
        bytes32 poolId = keccak256("pool1");

        address treasury = makeAddr("treasury");
        address buyback = makeAddr("buyback");
        address stakers = makeAddr("stakers");

        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);
        registry.setFeeAddresses(treasury, buyback, stakers);
        vm.stopPrank();

        // Generate fees
        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);

        uint256 fees = registry.getAccumulatedFees();
        assertGt(fees, 0);

        // Distribute
        registry.distributeFees();

        // Check distribution (50/30/20)
        uint256 treasuryBal = registry.balanceOf(treasury);
        uint256 buybackBal = registry.balanceOf(buyback);
        uint256 stakersBal = registry.balanceOf(stakers);

        assertGt(treasuryBal, 0);
        assertGt(buybackBal, 0);
        assertGt(stakersBal, 0);
        assertApproxEqRel(treasuryBal, (fees * 5000) / 10000, 0.01e18);
        assertApproxEqRel(buybackBal, (fees * 3000) / 10000, 0.01e18);

        // All fees distributed
        assertEq(registry.getAccumulatedFees(), 0);
    }

    function test_protocolFee_setFee() public {
        vm.prank(owner);
        registry.setProtocolFee(750); // 7.5%

        (uint64 feeBps,) = registry.getProtocolFeeConfig();
        assertEq(feeBps, 750);
    }

    function test_protocolFee_cannotExceedMax() public {
        vm.prank(owner);
        vm.expectRevert(FixerRegistryUpgradeable.FeeExceedsMax.selector);
        registry.setProtocolFee(1001); // > 10%
    }

    // ========================================================================
    // HOOK MANAGEMENT TESTS
    // ========================================================================

    function test_registerHook() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        assertTrue(registry.isAuthorizedHook(hookAddr));
    }

    function test_deregisterHook() public {
        bytes32 poolId = keccak256("pool1");

        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);
        registry.deregisterHook(hookAddr, poolId);
        vm.stopPrank();

        assertFalse(registry.isAuthorizedHook(hookAddr));
    }

    function test_registerHook_duplicateReverts() public {
        bytes32 poolId = keccak256("pool1");

        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);

        vm.expectRevert(FixerRegistryUpgradeable.HookAlreadyRegistered.selector);
        registry.registerHook(hookAddr, poolId);
        vm.stopPrank();
    }

    function test_registerHook_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.registerHook(hookAddr, keccak256("pool1"));
    }

    // ========================================================================
    // UPGRADE TESTS
    // ========================================================================

    function test_upgrade_ownerCanUpgrade() public {
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();

        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Still works after upgrade
        assertEq(registry.owner(), owner);
        assertEq(registry.VERSION(), 2_003_000);
    }

    function test_upgrade_nonOwnerReverts() public {
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();

        vm.prank(user1);
        vm.expectRevert();
        registry.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_preservesState() public {
        bytes32 poolId = keccak256("pool1");

        // Set up state
        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);
        registry.setProtocolFee(750);
        vm.stopPrank();

        // Record a referral
        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);

        // Snapshot state
        uint256 preSupply = registry.totalSupply();
        uint256 preUser1Bal = registry.balanceOf(user1);
        FixerRegistryStorage.ReferrerStats memory preStats = registry.getReferrerStats(user1);
        (uint64 preHookCount,,) = registry.getGlobalStats();
        (uint64 preFee,) = registry.getProtocolFeeConfig();

        // Upgrade
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();
        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Verify state preserved
        assertEq(registry.totalSupply(), preSupply);
        assertEq(registry.balanceOf(user1), preUser1Bal);
        assertEq(registry.owner(), owner);
        assertTrue(registry.isAuthorizedHook(hookAddr));

        FixerRegistryStorage.ReferrerStats memory postStats = registry.getReferrerStats(user1);
        assertEq(postStats.totalVolume, preStats.totalVolume);
        assertEq(postStats.referralCount, preStats.referralCount);
        assertEq(postStats.totalEarned, preStats.totalEarned);

        (uint64 postHookCount,,) = registry.getGlobalStats();
        assertEq(postHookCount, preHookCount);

        (uint64 postFee,) = registry.getProtocolFeeConfig();
        assertEq(postFee, preFee);
    }

    function test_upgrade_referralsStillWorkAfter() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Pre-upgrade referral
        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 1000e18, poolId);
        uint256 balBefore = registry.balanceOf(user1);

        // Upgrade
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();
        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Post-upgrade referral
        vm.prank(hookAddr);
        registry.recordReferral(user1, user2, 2000e18, poolId);

        assertGt(registry.balanceOf(user1), balBefore);
    }

    // ========================================================================
    // TIER PROGRESSION TESTS
    // ========================================================================

    function test_tierProgression() public {
        bytes32 poolId = keccak256("pool1");

        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Start at Bronze
        FixerRegistryStorage.ReferrerStats memory stats = registry.getReferrerStats(user1);
        assertEq(uint8(stats.tier), uint8(FixerRegistryStorage.ReferrerTier.Bronze));

        // Generate enough volume and referrals for Silver (10k volume, 10 referrals)
        for (uint256 i = 0; i < 10; i++) {
            address swapper = makeAddr(string(abi.encodePacked("swapper", i)));
            vm.prank(hookAddr);
            registry.recordReferral(user1, swapper, 1_100e18, poolId);
        }

        stats = registry.getReferrerStats(user1);
        assertEq(uint8(stats.tier), uint8(FixerRegistryStorage.ReferrerTier.Silver));
    }

    function test_tierProgress_viewFunction() public view {
        (
            FixerRegistryStorage.ReferrerTier current,
            FixerRegistryStorage.ReferrerTier next,
            uint256 volProgress,
            uint256 refProgress
        ) = registry.getProgressToNextTier(user1);

        assertEq(uint8(current), uint8(FixerRegistryStorage.ReferrerTier.Bronze));
        assertEq(uint8(next), uint8(FixerRegistryStorage.ReferrerTier.Silver));
        assertEq(volProgress, 0);
        assertEq(refProgress, 0);
    }

    // ========================================================================
    // ADMIN TESTS
    // ========================================================================

    function test_setRewardParameters() public {
        vm.prank(owner);
        registry.setRewardParameters(200e18, 20, 2000e18, 2e18);

        // Verify via calculateReward
        uint256 reward = registry.calculateReward(1000e18);
        // 1000 * 20 / 10000 = 2e18
        assertEq(reward, 2e18);
    }

    function test_setRewardParameters_invalidReverts() public {
        vm.prank(owner);
        vm.expectRevert(FixerRegistryUpgradeable.InvalidParameter.selector);
        registry.setRewardParameters(200e18, 20, 100e18, 200e18); // min > max
    }

    function test_setTierThresholds() public {
        FixerRegistryStorage.TierThresholds memory newThresholds = FixerRegistryStorage.TierThresholds({
            minVolume: 5_000e18,
            minReferrals: 5,
            multiplierBps: 11000
        });

        vm.prank(owner);
        registry.setTierThresholds(FixerRegistryStorage.ReferrerTier.Silver, newThresholds);

        FixerRegistryStorage.TierThresholds memory result =
            registry.getTierThresholds(FixerRegistryStorage.ReferrerTier.Silver);
        assertEq(result.minVolume, 5_000e18);
        assertEq(result.minReferrals, 5);
        assertEq(result.multiplierBps, 11000);
    }
}
