// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";
import {IFixerRegistryFull} from "./helpers/IFixerRegistryFull.sol";
import {FixerLib} from "../src/libraries/FixerLib.sol";
import {IAgentRegistry} from "../src/interfaces/IAgentRegistry.sol";
import {ERC8004Constants} from "../src/types/AgentTypes.sol";
import {IERC8004IdentityRegistry} from "../src/interfaces/IERC8004IdentityRegistry.sol";
import {IERC8004ReputationRegistry} from "../src/interfaces/IERC8004ReputationRegistry.sol";
import {IERC8004ValidationRegistry} from "../src/interfaces/IERC8004ValidationRegistry.sol";

// ============================================================================
// MOCK CONTRACTS (Agent Infrastructure Stack)
// ============================================================================

/// @notice Mock ERC-8004 Identity Registry for X402 tests
contract X402MockIdentityRegistry is IERC8004IdentityRegistry {
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public agentWallets;

    function setOwner(uint256 tokenId, address owner_) external {
        owners[tokenId] = owner_;
    }

    function setAgentWallet(uint256 agentId, address wallet) external {
        agentWallets[agentId] = wallet;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return agentWallets[agentId];
    }

    function getMetadata(uint256, string calldata) external pure returns (bytes memory) {
        return "";
    }
}

/// @notice Mock ERC-8004 Reputation Registry for X402 tests
contract X402MockReputationRegistry is IERC8004ReputationRegistry {
    mapping(uint256 => int128) public scores;
    mapping(uint256 => uint8) public scoreDecimals;

    function setScore(uint256 agentId, int128 score, uint8 decimals_) external {
        scores[agentId] = score;
        scoreDecimals[agentId] = decimals_;
    }

    function getSummary(
        uint256 agentId,
        address[] calldata,
        bytes32,
        bytes32
    ) external view returns (uint256 count, int128 summaryValue, uint8 decimals_) {
        return (1, scores[agentId], scoreDecimals[agentId]);
    }

    function readFeedback(uint256, address, uint256) external pure returns (int128, uint8, bytes32, bytes32, bool) {
        return (0, 0, bytes32(0), bytes32(0), false);
    }

    function giveFeedback(uint256, int128, uint8, bytes32, bytes32, bytes32, string calldata, bytes32) external {}
}

/// @notice Mock ERC-8004 Validation Registry for X402 tests
contract X402MockValidationRegistry is IERC8004ValidationRegistry {
    function getSummary(uint256, address[] calldata, bytes32) external pure returns (uint256 count, uint8 averageResponse) {
        return (1, 100);
    }
}

// ============================================================================
// AGENT INFRASTRUCTURE STACK: AGENT REGISTRATION TESTS
// ============================================================================

/// @title X402 Agent Registry Tests (Agent Infrastructure Stack)
/// @notice Tests for ERC-8004 agent registration, deregistration, and view functions
/// @dev All agent registration uses ERC-8004 NFT ownership proof (permissionless)
contract X402AgentRegistryTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    X402MockIdentityRegistry public identityRegistry;
    X402MockReputationRegistry public reputationRegistry;
    X402MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public agent3 = makeAddr("agent3");
    address public hookAddr = makeAddr("hook");

    uint256 public constant AGENT_ID_1 = 101;
    uint256 public constant AGENT_ID_2 = 102;
    uint256 public constant AGENT_ID_3 = 103;

    function setUp() public {
        identityRegistry = new X402MockIdentityRegistry();
        reputationRegistry = new X402MockReputationRegistry();
        validationRegistry = new X402MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        // Configure ERC-8004 registries
        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        // Register hook for referral tests
        vm.prank(owner);
        registry.registerHook(hookAddr, keccak256("test-pool"));

        // Set up identities
        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);
        identityRegistry.setOwner(AGENT_ID_2, agent2);
        identityRegistry.setAgentWallet(AGENT_ID_2, agent2);
        identityRegistry.setOwner(AGENT_ID_3, agent3);
        identityRegistry.setAgentWallet(AGENT_ID_3, agent3);
    }

    // ========================================================================
    // VERSION TESTS
    // ========================================================================

    function test_version_is_v2_5_0() public view {
        assertEq(registry.VERSION(), 2_006_000, "Should be v2.6.0");
    }

    // ========================================================================
    // AGENT REGISTRATION TESTS (ERC-8004 Permissionless)
    // ========================================================================

    function test_registerAgent_success() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        assertTrue(ext.isRegisteredAgent(agent1), "Agent should be registered");
        assertTrue(ext.isVerifiedAgent(agent1), "Agent should be verified");
        assertEq(ext.getTotalAgents(), 1, "Total agents should be 1");
        assertEq(
            ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw),
            1,
            "OpenClaw agent count should be 1"
        );
    }

    function test_registerAgent_profileData() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.Moltbook);

        FixerRegistryStorage.AgentProfile memory profile = ext.getAgentProfile(agent1);
        assertEq(profile.wallet, agent1, "Wallet should match");
        assertEq(profile.erc8004AgentId, AGENT_ID_1, "erc8004AgentId should match");
        assertEq(profile.registeredAt, block.timestamp, "registeredAt should be now");
        assertEq(uint8(profile.platform), uint8(FixerRegistryStorage.AgentPlatform.Moltbook), "Platform should be Moltbook");
        assertTrue(profile.verified, "Should be verified");
    }

    function test_registerAgent_multipleAgents() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.prank(agent2);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.Moltbook);

        vm.prank(agent3);
        ext.registerAgent(AGENT_ID_3, FixerRegistryStorage.AgentPlatform.Custom);

        assertEq(ext.getTotalAgents(), 3, "Should have 3 agents");
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 1);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Moltbook), 1);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Custom), 1);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Human), 0);
    }

    function test_registerAgent_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentRegistered(
            agent1,
            AGENT_ID_1,
            FixerRegistryStorage.AgentPlatform.OpenClaw
        );

        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_permissionless() public {
        // Anyone can register if they own the NFT — no owner gating
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
        assertTrue(ext.isRegisteredAgent(agent1));
    }

    function test_registerAgent_revert_notNFTOwner() public {
        // agent2 tries to register with agent1's NFT
        vm.prank(agent2);
        vm.expectRevert(IAgentRegistry.InvalidAgentIdOwnership.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_walletMismatch() public {
        identityRegistry.setAgentWallet(AGENT_ID_1, agent2);

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.AgentWalletMismatch.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_alreadyRegistered() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        // Same wallet tries again with different ID
        identityRegistry.setOwner(AGENT_ID_2, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_2, agent1);

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.AgentAlreadyRegistered.selector);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_agentIdAlreadyRegistered() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        // Transfer NFT to agent2 and try to register same ID
        identityRegistry.setOwner(AGENT_ID_1, agent2);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent2);

        vm.prank(agent2);
        vm.expectRevert(IAgentRegistry.AgentIdAlreadyRegistered.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_revert_registryNotConfigured() public {
        // Deploy fresh registry without ERC-8004 configuration
        FixerRegistryUpgradeable impl2 = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(impl2), initData);
        FixerRegistryUpgradeable reg2 = FixerRegistryUpgradeable(payable(address(proxy2)));
        FixerRegistryExtension ext2 = new FixerRegistryExtension();
        vm.prank(owner);
        reg2.setExtension(address(ext2));

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.ERC8004RegistryNotConfigured.selector);
        IFixerRegistryFull(address(proxy2)).registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    // ========================================================================
    // AGENT DEREGISTRATION TESTS
    // ========================================================================

    function test_deregisterAgent_success() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.prank(owner);
        ext.deregisterAgent(agent1);

        assertFalse(ext.isRegisteredAgent(agent1), "Agent should not be registered");
        assertFalse(ext.isVerifiedAgent(agent1), "Agent should not be verified");
        assertEq(ext.getTotalAgents(), 0, "Total agents should be 0");
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 0);
    }

    function test_deregisterAgent_emitsEvent() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.AgentDeregistered(agent1);

        vm.prank(owner);
        ext.deregisterAgent(agent1);
    }

    function test_deregisterAgent_revert_notRegistered() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        ext.deregisterAgent(agent1);
    }

    function test_deregisterAgent_revert_nonOwner() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.prank(agent1);
        vm.expectRevert();
        ext.deregisterAgent(agent1);
    }

    // ========================================================================
    // AGENT VIEW FUNCTION TESTS
    // ========================================================================

    function test_isRegisteredAgent_false_unregistered() public view {
        assertFalse(ext.isRegisteredAgent(agent1));
    }

    function test_isVerifiedAgent_false_unregistered() public view {
        assertFalse(ext.isVerifiedAgent(agent1));
    }

    function test_getAgentMultiplierBonus_zero_unregistered() public view {
        assertEq(ext.getAgentMultiplierBonus(agent1), 0);
    }

    function test_getAgentProfile_empty_unregistered() public view {
        FixerRegistryStorage.AgentProfile memory profile = ext.getAgentProfile(agent1);
        assertEq(profile.wallet, address(0), "Unregistered agent wallet should be zero");
    }

    function test_getTotalAgents_initial() public view {
        assertEq(ext.getTotalAgents(), 0, "Should start with 0 agents");
    }

    function test_getAgentCountByPlatform_initial() public view {
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw), 0);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Moltbook), 0);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Custom), 0);
        assertEq(ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.Human), 0);
    }
}

// ============================================================================
// REFERRAL DELEGATION TESTS
// ============================================================================

contract X402DelegationTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;

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
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));
    }

    // ---- Delegate Referral ----

    function test_delegateReferral_success() public {
        vm.prank(alice);
        ext.delegateReferral(bob);

        assertTrue(ext.isDelegated(alice, bob), "Alice should have delegated to Bob");
    }

    function test_delegateReferral_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.ReferralDelegated(alice, bob);

        vm.prank(alice);
        ext.delegateReferral(bob);
    }

    function test_delegateReferral_multipleRecipients() public {
        vm.startPrank(alice);
        ext.delegateReferral(bob);
        ext.delegateReferral(charlie);
        vm.stopPrank();

        assertTrue(ext.isDelegated(alice, bob), "Delegated to Bob");
        assertTrue(ext.isDelegated(alice, charlie), "Delegated to Charlie");
    }

    function test_delegateReferral_revert_self() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.CannotDelegateToSelf.selector);
        ext.delegateReferral(alice);
    }

    function test_delegateReferral_revert_zeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.InvalidAgentAddress.selector);
        ext.delegateReferral(address(0));
    }

    function test_delegateReferral_revert_alreadyExists() public {
        vm.startPrank(alice);
        ext.delegateReferral(bob);

        vm.expectRevert(IAgentRegistry.DelegationAlreadyExists.selector);
        ext.delegateReferral(bob);
        vm.stopPrank();
    }

    // ---- Revoke Delegation ----

    function test_revokeDelegation_success() public {
        vm.startPrank(alice);
        ext.delegateReferral(bob);
        ext.revokeDelegation(bob);
        vm.stopPrank();

        assertFalse(ext.isDelegated(alice, bob), "Delegation should be revoked");
    }

    function test_revokeDelegation_emitsEvent() public {
        vm.startPrank(alice);
        ext.delegateReferral(bob);

        vm.expectEmit(true, true, true, true);
        emit IAgentRegistry.ReferralDelegationRevoked(alice, bob);

        ext.revokeDelegation(bob);
        vm.stopPrank();
    }

    function test_revokeDelegation_revert_notDelegated() public {
        vm.prank(alice);
        vm.expectRevert(IAgentRegistry.DelegationNotFound.selector);
        ext.revokeDelegation(bob);
    }

    function test_delegationNotSymmetric() public {
        vm.prank(alice);
        ext.delegateReferral(bob);

        assertTrue(ext.isDelegated(alice, bob), "Alice -> Bob should be true");
        assertFalse(ext.isDelegated(bob, alice), "Bob -> Alice should be false");
    }
}

// ============================================================================
// AGENT BONUS MULTIPLIER IN REWARD COMPUTATION TESTS
// ============================================================================

/// @notice Tests that ERC-8004 reputation-derived bonuses affect reward computation
contract X402AgentBonusTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    X402MockIdentityRegistry public identityRegistry;
    X402MockReputationRegistry public reputationRegistry;
    X402MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public hookAddr = makeAddr("hook");
    bytes32 public poolId = keccak256("test-pool");

    address public agentReferrer = makeAddr("agentReferrer");
    address public normalReferrer = makeAddr("normalReferrer");
    address public swapper = makeAddr("swapper");

    uint256 public constant AGENT_ID = 42;

    function setUp() public {
        identityRegistry = new X402MockIdentityRegistry();
        reputationRegistry = new X402MockReputationRegistry();
        validationRegistry = new X402MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        // Configure ERC-8004 registries
        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        // Register hook
        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Set up agent identity with elite reputation (85 = 5000 BPS bonus)
        identityRegistry.setOwner(AGENT_ID, agentReferrer);
        identityRegistry.setAgentWallet(AGENT_ID, agentReferrer);
        reputationRegistry.setScore(AGENT_ID, 85, 0); // Elite tier

        // Register agent via ERC-8004
        vm.prank(agentReferrer);
        ext.registerAgent(AGENT_ID, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_agentReferrer_getsBonus() public {
        // Record a referral for agent referrer (has elite reputation bonus)
        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agentReferrer, swapper, 10_000e18, poolId);

        // For a normal referrer (no agent bonus), record a referral
        vm.prank(hookAddr);
        uint256 normalReward = registry.recordReferral(normalReferrer, swapper, 10_000e18, poolId);

        // Agent should earn more due to reputation-derived bonus
        assertGt(agentReward, normalReward, "Agent should earn more than normal referrer");
    }

    function test_agentReferrer_bonusDerivedFromReputation() public {
        // Agent has elite reputation (85 = 5000 BPS = 50% bonus)
        uint16 bonus = ext.getReputationBonus(agentReferrer);
        assertEq(bonus, ERC8004Constants.BONUS_ELITE, "Should have elite bonus from reputation");
    }

    function test_agentReferrer_noBonus_whenZeroReputation() public {
        // Set reputation to 0
        reputationRegistry.setScore(AGENT_ID, 0, 0);
        ext.refreshAgentReputation(agentReferrer);

        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agentReferrer, swapper, 10_000e18, poolId);

        vm.prank(hookAddr);
        uint256 normalReward = registry.recordReferral(normalReferrer, swapper, 10_000e18, poolId);

        // With 0 reputation, rewards should be equal
        assertEq(agentReward, normalReward, "0 reputation should yield same reward");
    }
}

// ============================================================================
// EIP-3009 TRANSFER WITH AUTHORIZATION TESTS (x402 Payment Layer)
// ============================================================================

contract X402TransferWithAuthorizationTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;

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
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

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
                ext.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
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
                ext.DOMAIN_SEPARATOR(),
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
        ext.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(registry.balanceOf(recipient), amount, "Recipient should receive tokens");
        assertEq(registry.balanceOf(signer), signerBalBefore - amount, "Signer balance should decrease");
    }

    function test_transferWithAuthorization_nonceUsed() public {
        uint256 amount = 1e18;
        bytes32 nonce = bytes32(uint256(42));

        assertFalse(ext.authorizationState(signer, nonce), "Nonce should not be used yet");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(
            signer, recipient, amount, block.timestamp - 1, block.timestamp + 3600, nonce
        );

        vm.prank(facilitator);
        ext.transferWithAuthorization(
            signer, recipient, amount, block.timestamp - 1, block.timestamp + 3600, nonce, v, r, s
        );

        assertTrue(ext.authorizationState(signer, nonce), "Nonce should be used after transfer");
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
        ext.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce, v, r, s
        );

        // Replay should fail
        vm.prank(facilitator);
        vm.expectRevert(FixerRegistryExtension.AuthorizationAlreadyUsed.selector);
        ext.transferWithAuthorization(
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
        vm.expectRevert(FixerLib.AuthorizationExpired.selector);
        ext.transferWithAuthorization(
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
        vm.expectRevert(FixerLib.AuthorizationNotYetValid.selector);
        ext.transferWithAuthorization(
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

        // Tamper: sign with wrong key
        bytes32 structHash = keccak256(
            abi.encode(
                ext.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                signer, recipient, amount, validAfter, validBefore, nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", ext.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPK, digest);

        vm.prank(facilitator);
        vm.expectRevert(FixerLib.InvalidSignature.selector);
        ext.transferWithAuthorization(
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
        ext.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce1, v1, r1, s1
        );

        // Transfer with nonce 2 should also succeed
        bytes32 nonce2 = bytes32(uint256(2));
        (uint8 v2, bytes32 r2, bytes32 s2) = _signTransferAuth(
            signer, recipient, amount, validAfter, validBefore, nonce2
        );
        vm.prank(facilitator);
        ext.transferWithAuthorization(
            signer, recipient, amount, validAfter, validBefore, nonce2, v2, r2, s2
        );

        assertEq(registry.balanceOf(recipient), amount * 2, "Should have received 2 transfers");
    }

    function test_DOMAIN_SEPARATOR_nonZero() public view {
        bytes32 ds = ext.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0), "DOMAIN_SEPARATOR should not be zero");
    }
}

// ============================================================================
// REINITIALIZE UPGRADE PATH TESTS
// ============================================================================

contract X402ReinitializeTest is Test {
    function test_reinitialize_setsEIP712() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (address(this), address(this), address(0))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        registry.setExtension(address(extensionImpl));
        IFixerRegistryFull ext_ = IFixerRegistryFull(address(proxy));

        // DOMAIN_SEPARATOR should already be set from initialize
        bytes32 ds = ext_.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0), "DOMAIN_SEPARATOR should be set from initialize");
    }

    function test_version_v2_5_0() public {
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (address(this), address(this), address(0))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));

        assertEq(registry.VERSION(), 2_006_000, "Version should be 2.5.0");
    }
}
