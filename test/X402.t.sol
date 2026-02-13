// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {IAgentRegistry} from "../src/interfaces/IAgentRegistry.sol";

/// @title x402 Enhancement Tests
/// @notice Comprehensive tests for x402 agent registry, referral delegation,
///         agent bonus multiplier, and EIP-3009 transferWithAuthorization
/// @dev Tests the v2.3.0 (x402) features of FixerRegistryUpgradeable
contract X402AgentRegistryTest is Test {
    // ========================================================================
    // STATE
    // ========================================================================

    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public agent3 = makeAddr("agent3");
    address public hookAddr = makeAddr("hook");

    bytes32 public constant PROOF_HASH_1 = keccak256("x402-proof-agent1");
    bytes32 public constant PROOF_HASH_2 = keccak256("x402-proof-agent2");
    bytes32 public constant PROOF_HASH_3 = keccak256("x402-proof-agent3");

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

        // Register a hook for referral tests
        vm.startPrank(owner);
        bytes32 poolId = keccak256("test-pool");
        registry.registerHook(hookAddr, poolId);
        vm.stopPrank();
    }

    // ========================================================================
    // VERSION TESTS
    // ========================================================================

    function test_version_is_2_3_0() public view {
        assertEq(registry.VERSION(), 2_003_000, "Should be v2.3.0");
    }

    // ========================================================================
    // AGENT REGISTRATION TESTS
    // ========================================================================

    function test_registerAgent_success() public {
        vm.prank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        assertTrue(registry.isRegisteredAgent(agent1), "Agent should be registered");
        assertTrue(registry.isVerifiedAgent(agent1), "Agent should be verified");
        assertEq(registry.getTotalAgents(), 1, "Total agents should be 1");
        assertEq(
            registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw),
            1,
            "OpenClaw agent count should be 1"
        );
    }

    function test_registerAgent_profileData() public {
        vm.prank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.Moltbook);

        FixerRegistryStorage.AgentProfile memory profile = registry.getAgentProfile(agent1);
        assertEq(profile.wallet, agent1, "Wallet should match");
        assertEq(profile.x402Identity, PROOF_HASH_1, "x402Identity should match");
        assertEq(profile.registeredAt, block.timestamp, "registeredAt should be now");
        assertEq(uint8(profile.platform), uint8(FixerRegistryStorage.AgentPlatform.Moltbook), "Platform should be Moltbook");
        assertEq(profile.x402Volume, 0, "x402Volume should be 0");
        assertTrue(profile.verified, "Should be verified");
        assertEq(profile.bonusMultiplierBps, 0, "bonusMultiplierBps should be 0");
    }

    function test_registerAgent_multipleAgents() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.registerAgent(agent2, PROOF_HASH_2, FixerRegistryStorage.AgentPlatform.Moltbook);
        registry.registerAgent(agent3, PROOF_HASH_3, FixerRegistryStorage.AgentPlatform.Custom);
        vm.stopPrank();

        assertEq(registry.getTotalAgents(), 3, "Should have 3 agents");
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 1);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Moltbook), 1);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Custom), 1);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Human), 0);
    }

    function test_registerAgent_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentRegistered(
            agent1,
            FixerRegistryStorage.AgentPlatform.OpenClaw,
            PROOF_HASH_1,
            owner
        );

        vm.prank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_nonOwner() public {
        vm.prank(agent1);
        vm.expectRevert();
        registry.registerAgent(agent2, PROOF_HASH_2, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.InvalidAgentAddress.selector);
        registry.registerAgent(address(0), PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_alreadyRegistered() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectRevert(IAgentRegistry.AgentAlreadyRegistered.selector);
        registry.registerAgent(agent1, PROOF_HASH_2, FixerRegistryStorage.AgentPlatform.OpenClaw);
        vm.stopPrank();
    }

    // ========================================================================
    // AGENT DEREGISTRATION TESTS
    // ========================================================================

    function test_deregisterAgent_success() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.deregisterAgent(agent1);
        vm.stopPrank();

        assertFalse(registry.isRegisteredAgent(agent1), "Agent should not be registered");
        assertFalse(registry.isVerifiedAgent(agent1), "Agent should not be verified");
        assertEq(registry.getTotalAgents(), 0, "Total agents should be 0");
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 0);
    }

    function test_deregisterAgent_emitsEvent() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentDeregistered(agent1);

        registry.deregisterAgent(agent1);
        vm.stopPrank();
    }

    function test_deregisterAgent_revert_notRegistered() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        registry.deregisterAgent(agent1);
    }

    function test_deregisterAgent_revert_nonOwner() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        vm.stopPrank();

        vm.prank(agent1);
        vm.expectRevert();
        registry.deregisterAgent(agent1);
    }

    // ========================================================================
    // AGENT PROFILE UPDATE TESTS
    // ========================================================================

    function test_updateAgentProfile_bonusAndVerified() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.updateAgentProfile(agent1, 2000, true); // 20% bonus, still verified
        vm.stopPrank();

        assertEq(registry.getAgentMultiplierBonus(agent1), 2000, "Bonus should be 2000 bps");
        assertTrue(registry.isVerifiedAgent(agent1), "Should still be verified");
    }

    function test_updateAgentProfile_unverify() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.updateAgentProfile(agent1, 0, false);
        vm.stopPrank();

        assertFalse(registry.isVerifiedAgent(agent1), "Should not be verified");
        assertEq(registry.getAgentMultiplierBonus(agent1), 0, "Unverified agent should have 0 bonus");
    }

    function test_updateAgentProfile_maxBonus() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.updateAgentProfile(agent1, 5000, true); // 50% max bonus
        vm.stopPrank();

        assertEq(registry.getAgentMultiplierBonus(agent1), 5000, "Should be max bonus");
    }

    function test_updateAgentProfile_emitsEvent() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentProfileUpdated(agent1, 3000, true);

        registry.updateAgentProfile(agent1, 3000, true);
        vm.stopPrank();
    }

    function test_updateAgentProfile_revert_notRegistered() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        registry.updateAgentProfile(agent1, 1000, true);
    }

    function test_updateAgentProfile_revert_bonusTooHigh() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectRevert(IAgentRegistry.BonusMultiplierTooHigh.selector);
        registry.updateAgentProfile(agent1, 5001, true); // Exceeds 5000 bps max
        vm.stopPrank();
    }

    // ========================================================================
    // AGENT X402 VOLUME TRACKING TESTS
    // ========================================================================

    function test_updateAgentX402Volume_success() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.updateAgentX402Volume(agent1, 1000e6); // 1000 USDC
        vm.stopPrank();

        FixerRegistryStorage.AgentProfile memory profile = registry.getAgentProfile(agent1);
        assertEq(profile.x402Volume, 1000e6, "x402Volume should be 1000 USDC");
    }

    function test_updateAgentX402Volume_accumulates() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        registry.updateAgentX402Volume(agent1, 500e6);
        registry.updateAgentX402Volume(agent1, 300e6);
        registry.updateAgentX402Volume(agent1, 200e6);
        vm.stopPrank();

        FixerRegistryStorage.AgentProfile memory profile = registry.getAgentProfile(agent1);
        assertEq(profile.x402Volume, 1000e6, "x402Volume should accumulate to 1000 USDC");
    }

    function test_updateAgentX402Volume_emitsEvent() public {
        vm.startPrank(owner);
        registry.registerAgent(agent1, PROOF_HASH_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentX402VolumeUpdated(agent1, 1000e6);

        registry.updateAgentX402Volume(agent1, 1000e6);
        vm.stopPrank();
    }

    function test_updateAgentX402Volume_revert_notRegistered() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        registry.updateAgentX402Volume(agent1, 1000e6);
    }

    // ========================================================================
    // AGENT VIEW FUNCTION TESTS
    // ========================================================================

    function test_isRegisteredAgent_false_unregistered() public view {
        assertFalse(registry.isRegisteredAgent(agent1));
    }

    function test_isVerifiedAgent_false_unregistered() public view {
        assertFalse(registry.isVerifiedAgent(agent1));
    }

    function test_getAgentMultiplierBonus_zero_unregistered() public view {
        assertEq(registry.getAgentMultiplierBonus(agent1), 0);
    }

    function test_getAgentProfile_empty_unregistered() public view {
        FixerRegistryStorage.AgentProfile memory profile = registry.getAgentProfile(agent1);
        assertEq(profile.wallet, address(0), "Unregistered agent wallet should be zero");
    }

    function test_getTotalAgents_initial() public view {
        assertEq(registry.getTotalAgents(), 0, "Should start with 0 agents");
    }

    function test_getAgentCountByPlatform_initial() public view {
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 0);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Moltbook), 0);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Custom), 0);
        assertEq(registry.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Human), 0);
    }
}

// ============================================================================
// REFERRAL DELEGATION TESTS
// ============================================================================

contract X402DelegationTest is Test {
    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));
    }

    // ---- Delegate Referral ----

    function test_delegateReferral_success() public {
        vm.prank(alice);
        registry.delegateReferral(bob);

        assertTrue(registry.isDelegated(alice, bob), "Alice should have delegated to Bob");
    }

    function test_delegateReferral_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.ReferralDelegated(alice, bob);

        vm.prank(alice);
        registry.delegateReferral(bob);
    }

    function test_delegateReferral_multipleRecipients() public {
        vm.startPrank(alice);
        registry.delegateReferral(bob);
        registry.delegateReferral(charlie);
        vm.stopPrank();

        assertTrue(registry.isDelegated(alice, bob), "Delegated to Bob");
        assertTrue(registry.isDelegated(alice, charlie), "Delegated to Charlie");
    }

    function test_delegateReferral_revert_self() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.CannotDelegateToSelf.selector);
        registry.delegateReferral(alice);
    }

    function test_delegateReferral_revert_zeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.InvalidAgentAddress.selector);
        registry.delegateReferral(address(0));
    }

    function test_delegateReferral_revert_alreadyExists() public {
        vm.startPrank(alice);
        registry.delegateReferral(bob);

        vm.expectRevert(IAgentRegistry.DelegationAlreadyExists.selector);
        registry.delegateReferral(bob);
        vm.stopPrank();
    }

    // ---- Revoke Delegation ----

    function test_revokeDelegation_success() public {
        vm.startPrank(alice);
        registry.delegateReferral(bob);
        registry.revokeDelegation(bob);
        vm.stopPrank();

        assertFalse(registry.isDelegated(alice, bob), "Delegation should be revoked");
    }

    function test_revokeDelegation_emitsEvent() public {
        vm.startPrank(alice);
        registry.delegateReferral(bob);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.ReferralDelegationRevoked(alice, bob);

        registry.revokeDelegation(bob);
        vm.stopPrank();
    }

    function test_revokeDelegation_revert_notDelegated() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.DelegationNotFound.selector);
        registry.revokeDelegation(bob);
    }

    function test_delegationNotSymmetric() public {
        vm.prank(alice);
        registry.delegateReferral(bob);

        assertTrue(registry.isDelegated(alice, bob), "Alice -> Bob should be true");
        assertFalse(registry.isDelegated(bob, alice), "Bob -> Alice should be false");
    }
}

// ============================================================================
// AGENT BONUS MULTIPLIER IN REWARD COMPUTATION TESTS
// ============================================================================

contract X402AgentBonusTest is Test {
    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public hookAddr = makeAddr("hook");
    bytes32 public poolId = keccak256("test-pool");

    address public agentReferrer = makeAddr("agentReferrer");
    address public normalReferrer = makeAddr("normalReferrer");
    address public swapper = makeAddr("swapper");

    function setUp() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));

        // Register hook
        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);

        // Register agent with 20% bonus
        registry.registerAgent(
            agentReferrer,
            keccak256("x402-proof"),
            FixerRegistryStorage.AgentPlatform.OpenClaw
        );
        registry.updateAgentProfile(agentReferrer, 2000, true); // 20% bonus
        vm.stopPrank();
    }

    function test_agentReferrer_getsBonus() public {
        // Record a referral for agent referrer
        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agentReferrer, swapper, 10_000e18, poolId);

        // For a normal referrer (no agent bonus), record a referral
        vm.prank(hookAddr);
        uint256 normalReward = registry.recordReferral(normalReferrer, swapper, 10_000e18, poolId);

        // Agent should earn more due to 20% bonus
        assertGt(agentReward, normalReward, "Agent should earn more than normal referrer");
    }

    function test_agentReferrer_noBonus_whenZeroBps() public {
        // Set bonus to 0
        vm.prank(owner);
        registry.updateAgentProfile(agentReferrer, 0, true);

        // Record referrals
        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agentReferrer, swapper, 10_000e18, poolId);

        vm.prank(hookAddr);
        uint256 normalReward = registry.recordReferral(normalReferrer, swapper, 10_000e18, poolId);

        // With 0 bonus bps, rewards should be equal
        assertEq(agentReward, normalReward, "0 bonus should yield same reward");
    }

    function test_agentReferrer_noBonus_whenUnverified() public {
        // Unverify the agent
        vm.prank(owner);
        registry.updateAgentProfile(agentReferrer, 2000, false);

        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agentReferrer, swapper, 10_000e18, poolId);

        vm.prank(hookAddr);
        uint256 normalReward = registry.recordReferral(normalReferrer, swapper, 10_000e18, poolId);

        assertEq(agentReward, normalReward, "Unverified agent should have no bonus");
    }
}

// ============================================================================
// EIP-3009 TRANSFER WITH AUTHORIZATION TESTS
// ============================================================================

contract X402TransferWithAuthorizationTest is Test {
    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public hookAddr = makeAddr("hook");
    bytes32 public poolId = keccak256("test-pool");

    // Use vm.addr to derive address from private key
    uint256 public signerPK = 0xA11CE;
    address public signer;

    address public recipient = makeAddr("recipient");
    address public facilitator = makeAddr("facilitator");

    function setUp() public {
        signer = vm.addr(signerPK);

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));

        // Register hook and give signer some FIX tokens via referral
        vm.startPrank(owner);
        registry.registerHook(hookAddr, poolId);
        vm.stopPrank();

        // Record referrals to mint FIX to signer
        vm.startPrank(hookAddr);
        for (uint256 i = 0; i < 10; i++) {
            registry.recordReferral(signer, makeAddr(string(abi.encodePacked("swapper", i))), 10_000e18, poolId);
        }
        vm.stopPrank();
    }

    function _signTransferAuth(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                registry.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                registry.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (v, r, s) = vm.sign(signerPK, digest);
    }

    function test_transferWithAuthorization_success() public {
        uint256 amount = 5e18; // 5 FIX
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 3600;

        uint256 signerBalBefore = registry.balanceOf(signer);

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce
        );

        // Facilitator submits the auth
        vm.prank(facilitator);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(registry.balanceOf(recipient), amount, "Recipient should receive tokens");
        assertEq(registry.balanceOf(signer), signerBalBefore - amount, "Signer balance should decrease");
    }

    function test_transferWithAuthorization_nonceUsed() public {
        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(42));

        assertFalse(registry.authorizationState(signer, nonce), "Nonce should not be used yet");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, block.timestamp - 1, block.timestamp + 3600, nonce
        );

        vm.prank(facilitator);
        registry.transferWithAuthorization(
            signer, recipient, amount, block.timestamp - 1, block.timestamp + 3600, nonce, v, r, s
        );

        assertTrue(registry.authorizationState(signer, nonce), "Nonce should be used after transfer");
    }

    function test_transferWithAuthorization_revert_replay() public {
        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 3600;

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce
        );

        // First transfer succeeds
        vm.prank(facilitator);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );

        // Replay should fail
        vm.prank(facilitator);
        vm.expectRevert(FixerRegistryUpgradeable.AuthorizationAlreadyUsed.selector);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );
    }

    function test_transferWithAuthorization_revert_expired() public {
        vm.warp(10_000); // Ensure block.timestamp is high enough

        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 3600;
        uint256 validBefore = block.timestamp - 1; // Already expired

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce
        );

        vm.prank(facilitator);
        vm.expectRevert(FixerRegistryUpgradeable.AuthorizationExpired.selector);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );
    }

    function test_transferWithAuthorization_revert_notYetValid() public {
        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp + 3600; // Not valid yet
        uint256 validBefore = block.timestamp + 7200;

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce
        );

        vm.prank(facilitator);
        vm.expectRevert(FixerRegistryUpgradeable.AuthorizationNotYetValid.selector);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );
    }

    function test_transferWithAuthorization_revert_invalidSignature() public {
        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 3600;

        // Sign with a DIFFERENT private key
        uint256 wrongPK = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce
        );

        // Tamper: sign with wrong key
        bytes32 structHash = keccak256(
            abi.encode(
                registry.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, recipient, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(wrongPK, digest);

        vm.prank(facilitator);
        vm.expectRevert(FixerRegistryUpgradeable.InvalidSignature.selector);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );
    }

    function test_transferWithAuthorization_differentNonces() public {
        uint256 amount = 1e18;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 3600;

        // Transfer with nonce 1
        bytes32 nonce1 = bytes32(uint256(1));
        (uint8 v1, bytes32 r1, bytes32 s1) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce1
        );
        vm.prank(facilitator);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce1, v1, r1, s1
        );

        // Transfer with nonce 2 should also succeed
        bytes32 nonce2 = bytes32(uint256(2));
        (uint8 v2, bytes32 r2, bytes32 s2) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce2
        );
        vm.prank(facilitator);
        registry.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce2, v2, r2, s2
        );

        assertEq(registry.balanceOf(recipient), amount * 2, "Should have received 2 transfers");
    }

    function test_DOMAIN_SEPARATOR_nonZero() public view {
        bytes32 ds = registry.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0), "DOMAIN_SEPARATOR should not be zero");
    }
}

// ============================================================================
// REINITIALIZE v3 UPGRADE PATH TEST
// ============================================================================

contract X402ReinitializeTest is Test {
    function test_reinitializeV3_setsEIP712() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (address(this), address(this), address(0))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(address(proxy));

        // DOMAIN_SEPARATOR should already be set from initialize
        bytes32 ds = registry.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0), "DOMAIN_SEPARATOR should be set from initialize");
    }

    function test_version_2_3_0() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (address(this), address(this), address(0))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(address(proxy));

        assertEq(registry.VERSION(), 2_003_000, "Version should be 2.3.0");
    }
}

// ============================================================================
// FUZZ TESTS
// ============================================================================

contract X402FuzzTest is Test {
    FixerRegistryUpgradeable public registry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");

    function setUp() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(address(proxy));
    }

    function testFuzz_registerAgent_arbitraryPlatform(uint8 platformRaw) public {
        vm.assume(platformRaw <= uint8(type(FixerRegistryStorage.AgentPlatform).max));
        address agent = makeAddr(string(abi.encodePacked("fuzz-agent-", platformRaw)));

        vm.prank(owner);
        registry.registerAgent(
            agent,
            keccak256(abi.encodePacked("proof-", platformRaw)),
            FixerRegistryStorage.AgentPlatform(platformRaw)
        );

        assertTrue(registry.isRegisteredAgent(agent));
        assertEq(registry.getTotalAgents(), 1);
    }

    function testFuzz_updateAgentProfile_bonusBounds(uint16 bonusBps) public {
        bonusBps = uint16(bound(bonusBps, 0, 5000)); // MAX_AGENT_BONUS_BPS

        address agent = makeAddr("fuzz-agent");
        vm.startPrank(owner);
        registry.registerAgent(
            agent,
            keccak256("proof"),
            FixerRegistryStorage.AgentPlatform.OpenClaw
        );
        registry.updateAgentProfile(agent, bonusBps, true);
        vm.stopPrank();

        assertEq(registry.getAgentMultiplierBonus(agent), bonusBps);
    }

    function testFuzz_updateAgentProfile_revert_bonusTooHigh(uint16 bonusBps) public {
        vm.assume(bonusBps > 5000);

        address agent = makeAddr("fuzz-agent");
        vm.startPrank(owner);
        registry.registerAgent(
            agent,
            keccak256("proof"),
            FixerRegistryStorage.AgentPlatform.OpenClaw
        );

        vm.expectRevert(IAgentRegistry.BonusMultiplierTooHigh.selector);
        registry.updateAgentProfile(agent, bonusBps, true);
        vm.stopPrank();
    }

    function testFuzz_x402Volume_accumulates(uint128 vol1, uint128 vol2) public {
        // Bound to prevent overflow
        vol1 = uint128(bound(vol1, 0, type(uint128).max / 2));
        vol2 = uint128(bound(vol2, 0, type(uint128).max / 2));

        address agent = makeAddr("fuzz-agent");
        vm.startPrank(owner);
        registry.registerAgent(
            agent,
            keccak256("proof"),
            FixerRegistryStorage.AgentPlatform.Moltbook
        );
        registry.updateAgentX402Volume(agent, vol1);
        registry.updateAgentX402Volume(agent, vol2);
        vm.stopPrank();

        FixerRegistryStorage.AgentProfile memory profile = registry.getAgentProfile(agent);
        assertEq(profile.x402Volume, vol1 + vol2, "Volume should accumulate");
    }
}
