// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {EmergencyModule} from "../src/modules/EmergencyModule.sol";

/// @title EmergencyModuleTest
/// @notice Tests for EmergencyModule: pause/resume, circuit breaker, access control
contract EmergencyModuleTest is Test {
    // ========================================================================
    // STATE
    // ========================================================================

    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public hookAddr = makeAddr("hook");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    bytes32 public poolId = keccak256("pool1");

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));

        // Register hook for referral tests
        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);
    }

    // ========================================================================
    // PAUSE REFERRALS
    // ========================================================================

    function test_pauseReferrals_securityCouncil() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        (bool paused,,,,,,,,,) = registry.getEmergencyState();
        assertTrue(paused);
    }

    function test_pauseReferrals_blocksRecordReferral() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        vm.prank(hookAddr);
        vm.expectRevert(EmergencyModule.ReferralSystemPaused.selector);
        registry.recordReferral(user1, user2, 1000e18, poolId);
    }

    function test_pauseReferrals_nonCouncilReverts() public {
        vm.prank(attacker);
        vm.expectRevert(EmergencyModule.NotSecurityCouncil.selector);
        registry.pauseReferrals();
    }

    function test_pauseReferrals_alreadyPausedReverts() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.ReferralsAlreadyPaused.selector);
        registry.pauseReferrals();
    }

    // ========================================================================
    // RESUME REFERRALS (within 7 days)
    // ========================================================================

    function test_resumeReferrals_withinThreshold_securityCouncil() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        // Resume within 7 days
        vm.warp(block.timestamp + 3 days);

        vm.prank(securityCouncil);
        registry.resumeReferrals();

        (bool paused,,,,,,,,,) = registry.getEmergencyState();
        assertFalse(paused);
    }

    function test_resumeReferrals_withinThreshold_governance() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        vm.prank(governance);
        registry.resumeReferrals();

        (bool paused,,,,,,,,,) = registry.getEmergencyState();
        assertFalse(paused);
    }

    function test_resumeReferrals_withinThreshold_attackerReverts() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        vm.prank(attacker);
        vm.expectRevert(EmergencyModule.NotSecurityCouncilOrGovernance.selector);
        registry.resumeReferrals();
    }

    // ========================================================================
    // RESUME REFERRALS (after 7 days — DAO required)
    // ========================================================================

    function test_resumeReferrals_afterThreshold_requiresDAO() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        // Warp past 7 days
        vm.warp(block.timestamp + 8 days);

        // Security council can't resume after 7 days
        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.DAOVoteRequiredForResume.selector);
        registry.resumeReferrals();
    }

    function test_resumeReferrals_afterThreshold_governanceCanResume() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        vm.warp(block.timestamp + 8 days);

        // DAO governance CAN resume
        vm.prank(governance);
        registry.resumeReferrals();

        (bool paused,,,,,,,,,) = registry.getEmergencyState();
        assertFalse(paused);
    }

    // ========================================================================
    // PAUSE AGENTS
    // ========================================================================

    function test_pauseAgents() public {
        vm.prank(securityCouncil);
        registry.pauseAgents();

        (, bool agentsPaused,,,,,,,,) = registry.getEmergencyState();
        assertTrue(agentsPaused);
    }

    function test_resumeAgents() public {
        vm.prank(securityCouncil);
        registry.pauseAgents();

        vm.prank(securityCouncil);
        registry.resumeAgents();

        (, bool agentsPaused,,,,,,,,) = registry.getEmergencyState();
        assertFalse(agentsPaused);
    }

    // ========================================================================
    // PAUSE REWARDS
    // ========================================================================

    function test_pauseRewards() public {
        vm.prank(securityCouncil);
        registry.pauseRewards();

        (,, bool rewardsPaused,,,,,,,) = registry.getEmergencyState();
        assertTrue(rewardsPaused);
    }

    function test_pauseRewards_blocksRecordReferral() public {
        vm.prank(securityCouncil);
        registry.pauseRewards();

        vm.prank(hookAddr);
        vm.expectRevert(EmergencyModule.RewardSystemPaused.selector);
        registry.recordReferral(user1, user2, 1000e18, poolId);
    }

    // ========================================================================
    // PAUSE ALL / RESUME ALL
    // ========================================================================

    function test_pauseAll() public {
        vm.prank(securityCouncil);
        registry.pauseAll();

        (bool refPaused, bool agentPaused, bool rewardPaused,,,,,,,) = registry.getEmergencyState();
        assertTrue(refPaused);
        assertTrue(agentPaused);
        assertTrue(rewardPaused);
    }

    function test_resumeAll_withinThreshold() public {
        vm.prank(securityCouncil);
        registry.pauseAll();

        vm.prank(securityCouncil);
        registry.resumeAll();

        (bool refPaused, bool agentPaused, bool rewardPaused,,,,,,,) = registry.getEmergencyState();
        assertFalse(refPaused);
        assertFalse(agentPaused);
        assertFalse(rewardPaused);
    }

    function test_resumeAll_afterThreshold_requiresDAO() public {
        vm.prank(securityCouncil);
        registry.pauseAll();

        vm.warp(block.timestamp + 8 days);

        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.DAOVoteRequiredForResume.selector);
        registry.resumeAll();
    }

    // ========================================================================
    // INDEPENDENT PAUSE STATES
    // ========================================================================

    function test_independentPauseStates() public {
        // Only pause referrals
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        (bool refPaused, bool agentPaused, bool rewardPaused,,,,,,,) = registry.getEmergencyState();
        assertTrue(refPaused);
        assertFalse(agentPaused);
        assertFalse(rewardPaused);

        // Pause agents separately
        vm.prank(securityCouncil);
        registry.pauseAgents();

        (, agentPaused,,,,,,,,) = registry.getEmergencyState();
        assertTrue(agentPaused);
    }

    // ========================================================================
    // CIRCUIT BREAKER
    // ========================================================================

    function test_circuitBreaker_triggersOnExcessiveMinting() public {
        // Set circuit breaker to minimum allowed threshold (100k FIX)
        vm.prank(securityCouncil);
        registry.setCircuitBreakerThreshold(100_000e18);

        // Set reward rate high so we can trigger circuit breaker
        vm.prank(owner);
        registry.setRewardParameters(
            1e18,       // min swap = 1
            10000,      // 100% reward rate
            type(uint128).max,
            0
        );

        // Record referrals that generate > 100k FIX total
        // Each referral at 20_000e18 volume with 100% rate generates ~19_000e18 FIX (minus 5% fee)
        // After circuit breaker triggers, rewards get paused and subsequent calls revert
        bool triggered = false;
        for (uint256 i = 0; i < 10; i++) {
            address swapper = makeAddr(string(abi.encodePacked("sw", i)));
            vm.prank(hookAddr);
            try registry.recordReferral(user1, swapper, 20_000e18, poolId) {
                // Succeeded — check if circuit breaker triggered
                (,, bool rewardsPaused,,,,,,,) = registry.getEmergencyState();
                if (rewardsPaused) {
                    triggered = true;
                    break;
                }
            } catch {
                // Once paused, subsequent calls revert — circuit breaker was triggered
                triggered = true;
                break;
            }
        }

        assertTrue(triggered, "Circuit breaker should have triggered");
        (,, bool rewardsPaused,,,,,,,) = registry.getEmergencyState();
        assertTrue(rewardsPaused);
    }

    function test_circuitBreaker_resetsAfterHour() public {
        // Set circuit breaker to minimum allowed threshold
        vm.prank(securityCouncil);
        registry.setCircuitBreakerThreshold(100_000e18);

        // Set reward rate high
        vm.prank(owner);
        registry.setRewardParameters(
            1e18,       // min swap = 1
            10000,      // 100% reward rate
            type(uint128).max,
            0
        );

        // Make referrals to approach threshold
        for (uint256 i = 0; i < 3; i++) {
            address swapper = makeAddr(string(abi.encodePacked("cbs", i)));
            vm.prank(hookAddr);
            registry.recordReferral(user1, swapper, 10_000e18, poolId);
        }

        // Warp past 1 hour (resets counter)
        vm.warp(block.timestamp + 1 hours + 1);

        // Should NOT be paused from this new referral alone (counter was reset)
        address user3 = makeAddr("user3");
        vm.prank(hookAddr);
        registry.recordReferral(user1, user3, 1000e18, poolId);

        (,, bool rewardsPaused,,,,,,,) = registry.getEmergencyState();
        assertFalse(rewardsPaused);
    }

    function test_setCircuitBreakerThreshold() public {
        vm.prank(securityCouncil);
        registry.setCircuitBreakerThreshold(500_000e18);

        (,,,,,, uint256 threshold,,,) = registry.getEmergencyState();
        assertEq(threshold, 500_000e18);
    }

    function test_setCircuitBreakerThreshold_attackerReverts() public {
        vm.prank(attacker);
        vm.expectRevert(EmergencyModule.NotSecurityCouncilOrGovernance.selector);
        registry.setCircuitBreakerThreshold(0);
    }

    // ========================================================================
    // ADMIN: SECURITY COUNCIL & GOVERNANCE
    // ========================================================================

    function test_setSecurityCouncil() public {
        address newCouncil = makeAddr("newCouncil");

        vm.prank(securityCouncil);
        registry.setSecurityCouncil(newCouncil);

        (,,,,,,,,address sc,) = registry.getEmergencyState();
        assertEq(sc, newCouncil);
    }

    function test_setSecurityCouncil_zeroReverts() public {
        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.ZeroAddress.selector);
        registry.setSecurityCouncil(address(0));
    }

    function test_setGovernance() public {
        address newGov = makeAddr("newGov");

        vm.prank(governance);
        registry.setGovernance(newGov);

        (,,,,,,,,,address gov) = registry.getEmergencyState();
        assertEq(gov, newGov);
    }

    // ========================================================================
    // REFERRAL WORKS AFTER RESUME
    // ========================================================================

    function test_referral_worksAfterResume() public {
        // Pause
        vm.prank(securityCouncil);
        registry.pauseAll();

        // Resume
        vm.prank(securityCouncil);
        registry.resumeAll();

        // Referral should work
        vm.prank(hookAddr);
        uint256 reward = registry.recordReferral(user1, user2, 1000e18, poolId);
        assertGt(reward, 0);
    }

    // ========================================================================
    // AUDIT FIX: PER-STATE TIMESTAMPS (prevents DAO threshold bypass)
    // ========================================================================

    /// @notice Verifies that each pause state has its own timestamp
    /// @dev HIGH finding: previously a single pausedAt was shared, allowing
    ///      a second pause action to reset the 7-day DAO timer for an earlier pause
    function test_perStateTimestamps_noDaoBypass() public {
        // Pause referrals at time T
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        // Warp 5 days
        vm.warp(block.timestamp + 5 days);

        // Pause agents at T+5 days
        vm.prank(securityCouncil);
        registry.pauseAgents();

        // Warp 3 more days (referrals now paused 8 days, agents 3 days)
        vm.warp(block.timestamp + 3 days);

        // Referrals paused > 7 days — only DAO can resume
        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.DAOVoteRequiredForResume.selector);
        registry.resumeReferrals();

        // But agents paused only 3 days — security council can still resume
        vm.prank(securityCouncil);
        registry.resumeAgents();

        // DAO can resume referrals
        vm.prank(governance);
        registry.resumeReferrals();
    }

    /// @notice Verify timestamps are reset to 0 on resume
    function test_perStateTimestamps_resetOnResume() public {
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        (,,, uint256 refAt,,,,,,) = registry.getEmergencyState();
        assertGt(refAt, 0, "timestamp should be set");

        vm.prank(securityCouncil);
        registry.resumeReferrals();

        (,,, uint256 refAtAfter,,,,,,) = registry.getEmergencyState();
        assertEq(refAtAfter, 0, "timestamp should reset on resume");
    }

    /// @notice Verify resumeAll uses the earliest (longest paused) timestamp
    function test_resumeAll_usesEarliestTimestamp() public {
        // Pause referrals at T
        vm.prank(securityCouncil);
        registry.pauseReferrals();

        // Warp 5 days, pause rewards
        vm.warp(block.timestamp + 5 days);
        vm.prank(securityCouncil);
        registry.pauseRewards();

        // Warp 3 more days (referrals=8 days, rewards=3 days)
        vm.warp(block.timestamp + 3 days);

        // resumeAll should require DAO since referrals are paused > 7 days
        vm.prank(securityCouncil);
        vm.expectRevert(EmergencyModule.DAOVoteRequiredForResume.selector);
        registry.resumeAll();

        // DAO can resumeAll
        vm.prank(governance);
        registry.resumeAll();

        (bool ref, bool agents, bool rewards,,,,,,,) = registry.getEmergencyState();
        assertFalse(ref);
        assertFalse(agents);
        assertFalse(rewards);
    }

    /// @notice Verify safe cast bounds check in setRewardParameters
    function test_setRewardParameters_overflowReverts() public {
        vm.prank(owner);
        vm.expectRevert(FixerRegistryUpgradeable.InvalidParameter.selector);
        registry.setRewardParameters(
            uint256(type(uint128).max) + 1, // exceeds uint128
            100,
            1000e18,
            1e18
        );
    }
}
