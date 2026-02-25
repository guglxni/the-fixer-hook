// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {IAgentRegistry} from "../src/interfaces/IAgentRegistry.sol";
import {IFixerRegistryFull} from "./helpers/IFixerRegistryFull.sol";
import {ERC8004Constants, XMTPConstants} from "../src/types/AgentTypes.sol";
import {IERC8004IdentityRegistry} from "../src/interfaces/IERC8004IdentityRegistry.sol";
import {IERC8004ReputationRegistry} from "../src/interfaces/IERC8004ReputationRegistry.sol";
import {IERC8004ValidationRegistry} from "../src/interfaces/IERC8004ValidationRegistry.sol";

// ============================================================================
// MOCK CONTRACTS (same as ERC8004.t.sol)
// ============================================================================

contract MockIdentityRegistryXMTP is IERC8004IdentityRegistry {
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

contract MockReputationRegistryXMTP is IERC8004ReputationRegistry {
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

// ============================================================================
// TEST: XMTP COMMUNICATION
// ============================================================================

contract XMTPCommunicationTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistryXMTP public identityRegistry;
    MockReputationRegistryXMTP public reputationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public nonAgent = makeAddr("nonAgent");

    uint256 public constant AGENT_ID_1 = 42;
    uint256 public constant AGENT_ID_2 = 99;
    bytes32 public constant XMTP_KEY_HASH_1 = keccak256("agent1-xmtp-installation-key");
    bytes32 public constant XMTP_KEY_HASH_2 = keccak256("agent2-xmtp-installation-key");
    string public constant ENDPOINT_1 = "xmtp://0xAgent1/inbox";
    string public constant ENDPOINT_2 = "xmtp://0xAgent2/inbox";

    function setUp() public {
        identityRegistry = new MockIdentityRegistryXMTP();
        reputationRegistry = new MockReputationRegistryXMTP();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        // Configure registries
        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(0)
        );

        // Run XMTP reinitializer
        registry.reinitializeV5();

        // Deploy extension
        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        // Set up identity for agents
        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);
        identityRegistry.setOwner(AGENT_ID_2, agent2);
        identityRegistry.setAgentWallet(AGENT_ID_2, agent2);

        // Register agent1
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    // ========================================================================
    // enableXMTP
    // ========================================================================

    function test_enableXMTP_success() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        assertTrue(ext.isXMTPEnabled(agent1));
        assertEq(ext.getXMTPPublicKeyHash(agent1), XMTP_KEY_HASH_1);
        assertEq(ext.getXMTPEndpoint(agent1), ENDPOINT_1);
        assertEq(ext.getXMTPEnabledCount(), 1);
    }

    function test_enableXMTP_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAgentRegistry.XMTPEndpointUpdated(agent1, XMTP_KEY_HASH_1, ENDPOINT_1);

        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);
    }

    function test_enableXMTP_multipleAgents() public {
        // Register and enable agent2
        vm.prank(agent2);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.Moltbook);

        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        vm.prank(agent2);
        ext.enableXMTP(XMTP_KEY_HASH_2, ENDPOINT_2);

        assertEq(ext.getXMTPEnabledCount(), 2);
        assertTrue(ext.isXMTPEnabled(agent1));
        assertTrue(ext.isXMTPEnabled(agent2));
    }

    function test_enableXMTP_updateExisting() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        // Re-enable with new key — should update without incrementing count
        bytes32 newKeyHash = keccak256("new-key");
        string memory newEndpoint = "xmtp://0xAgent1/inbox-v2";

        vm.prank(agent1);
        ext.enableXMTP(newKeyHash, newEndpoint);

        assertEq(ext.getXMTPPublicKeyHash(agent1), newKeyHash);
        assertEq(ext.getXMTPEndpoint(agent1), newEndpoint);
        assertEq(ext.getXMTPEnabledCount(), 1); // Still 1, not 2
    }

    function test_enableXMTP_revertNotRegistered() public {
        vm.prank(nonAgent);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);
    }

    function test_enableXMTP_revertZeroPublicKey() public {
        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.XMTPInvalidPublicKey.selector);
        ext.enableXMTP(bytes32(0), ENDPOINT_1);
    }

    function test_enableXMTP_revertEndpointTooLong() public {
        // Build a string > 256 chars
        bytes memory longUri = new bytes(257);
        for (uint256 i; i < 257; i++) {
            longUri[i] = "A";
        }

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.XMTPEndpointTooLong.selector);
        ext.enableXMTP(XMTP_KEY_HASH_1, string(longUri));
    }

    function test_enableXMTP_maxLengthEndpoint() public {
        // Exactly 256 chars should succeed
        bytes memory maxUri = new bytes(256);
        for (uint256 i; i < 256; i++) {
            maxUri[i] = "B";
        }

        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, string(maxUri));

        assertTrue(ext.isXMTPEnabled(agent1));
        assertEq(bytes(ext.getXMTPEndpoint(agent1)).length, 256);
    }

    // ========================================================================
    // disableXMTP
    // ========================================================================

    function test_disableXMTP_success() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        vm.prank(agent1);
        ext.disableXMTP();

        assertFalse(ext.isXMTPEnabled(agent1));
        assertEq(ext.getXMTPPublicKeyHash(agent1), bytes32(0));
        assertEq(ext.getXMTPEndpoint(agent1), "");
        assertEq(ext.getXMTPEnabledCount(), 0);
    }

    function test_disableXMTP_emitsEvent() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        vm.expectEmit(true, false, false, true);
        emit IAgentRegistry.XMTPDisabled(agent1);

        vm.prank(agent1);
        ext.disableXMTP();
    }

    function test_disableXMTP_revertNotRegistered() public {
        vm.prank(nonAgent);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        ext.disableXMTP();
    }

    function test_disableXMTP_revertNotEnabled() public {
        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.XMTPNotEnabled.selector);
        ext.disableXMTP();
    }

    function test_disableXMTP_decrementsCount() public {
        // Register agent2
        vm.prank(agent2);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.Custom);

        // Enable both
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);
        vm.prank(agent2);
        ext.enableXMTP(XMTP_KEY_HASH_2, ENDPOINT_2);

        assertEq(ext.getXMTPEnabledCount(), 2);

        // Disable agent1
        vm.prank(agent1);
        ext.disableXMTP();

        assertEq(ext.getXMTPEnabledCount(), 1);
        assertTrue(ext.isXMTPEnabled(agent2));
    }

    // ========================================================================
    // updateXMTPEndpoint
    // ========================================================================

    function test_updateXMTPEndpoint_success() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        string memory newEndpoint = "xmtp://0xAgent1/new-inbox";

        vm.prank(agent1);
        ext.updateXMTPEndpoint(newEndpoint);

        assertEq(ext.getXMTPEndpoint(agent1), newEndpoint);
        // Public key hash unchanged
        assertEq(ext.getXMTPPublicKeyHash(agent1), XMTP_KEY_HASH_1);
    }

    function test_updateXMTPEndpoint_emitsEvent() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        string memory newEndpoint = "xmtp://0xAgent1/updated";

        vm.expectEmit(true, false, false, true);
        emit IAgentRegistry.XMTPEndpointUpdated(agent1, XMTP_KEY_HASH_1, newEndpoint);

        vm.prank(agent1);
        ext.updateXMTPEndpoint(newEndpoint);
    }

    function test_updateXMTPEndpoint_revertNotEnabled() public {
        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.XMTPNotEnabled.selector);
        ext.updateXMTPEndpoint("xmtp://new-endpoint");
    }

    function test_updateXMTPEndpoint_revertNotRegistered() public {
        vm.prank(nonAgent);
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        ext.updateXMTPEndpoint("xmtp://foo");
    }

    function test_updateXMTPEndpoint_revertTooLong() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        bytes memory longUri = new bytes(257);
        for (uint256 i; i < 257; i++) {
            longUri[i] = "X";
        }

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.XMTPEndpointTooLong.selector);
        ext.updateXMTPEndpoint(string(longUri));
    }

    // ========================================================================
    // View functions — default state
    // ========================================================================

    function test_isXMTPEnabled_defaultFalse() public view {
        assertFalse(ext.isXMTPEnabled(agent1));
    }

    function test_getXMTPPublicKeyHash_defaultZero() public view {
        assertEq(ext.getXMTPPublicKeyHash(agent1), bytes32(0));
    }

    function test_getXMTPEndpoint_defaultEmpty() public view {
        assertEq(ext.getXMTPEndpoint(agent1), "");
    }

    function test_getXMTPEnabledCount_defaultZero() public view {
        assertEq(ext.getXMTPEnabledCount(), 0);
    }

    function test_isXMTPEnabled_nonExistentAgent() public view {
        assertFalse(ext.isXMTPEnabled(address(0xdead)));
    }

    // ========================================================================
    // deregisterAgent clears XMTP state
    // ========================================================================

    function test_deregisterAgent_clearsXMTP() public {
        // Enable XMTP
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);
        assertEq(ext.getXMTPEnabledCount(), 1);

        // Deregister (owner only)
        vm.prank(owner);
        ext.deregisterAgent(agent1);

        // XMTP state should be cleared (delete clears entire struct)
        assertFalse(ext.isXMTPEnabled(agent1));
        assertEq(ext.getXMTPPublicKeyHash(agent1), bytes32(0));
        assertEq(ext.getXMTPEndpoint(agent1), "");
        assertEq(ext.getXMTPEnabledCount(), 0);
    }

    // ========================================================================
    // VERSION check
    // ========================================================================

    function test_version_is_2_006_000() public view {
        assertEq(registry.VERSION(), 2_006_000);
    }

    // ========================================================================
    // reinitializeV5 checkpoint
    // ========================================================================

    function test_reinitializeV5_cannotRunTwice() public {
        // reinitializeV5 was already called in setUp
        vm.expectRevert();
        registry.reinitializeV5();
    }

    // ========================================================================
    // XMTP + ERC-8004 integration
    // ========================================================================

    function test_agentProfile_containsXMTPFields() public {
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, ENDPOINT_1);

        FixerRegistryStorage.AgentProfile memory profile = ext.getAgentProfile(agent1);
        assertTrue(profile.xmtpEnabled);
        assertEq(profile.xmtpPublicKeyHash, XMTP_KEY_HASH_1);
        assertEq(profile.xmtpEndpointUri, ENDPOINT_1);
        // Also verify ERC-8004 fields are intact
        assertTrue(profile.verified);
        assertEq(profile.erc8004AgentId, AGENT_ID_1);
    }

    function test_fullLifecycle_registerEnableDisableDeregister() public {
        // Agent2 registers
        vm.prank(agent2);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.Custom);

        // Enable XMTP
        vm.prank(agent2);
        ext.enableXMTP(XMTP_KEY_HASH_2, ENDPOINT_2);
        assertEq(ext.getXMTPEnabledCount(), 1);

        // Update endpoint
        vm.prank(agent2);
        ext.updateXMTPEndpoint("xmtp://updated");
        assertEq(ext.getXMTPEndpoint(agent2), "xmtp://updated");

        // Disable XMTP
        vm.prank(agent2);
        ext.disableXMTP();
        assertEq(ext.getXMTPEnabledCount(), 0);

        // Re-enable
        vm.prank(agent2);
        ext.enableXMTP(keccak256("new-key"), "xmtp://re-enabled");
        assertEq(ext.getXMTPEnabledCount(), 1);

        // Deregister clears everything
        vm.prank(owner);
        ext.deregisterAgent(agent2);
        assertEq(ext.getXMTPEnabledCount(), 0);
        assertFalse(ext.isXMTPEnabled(agent2));
    }

    function test_enableXMTP_emptyEndpoint() public {
        // Empty endpoint URI is valid (agent may publish key only)
        vm.prank(agent1);
        ext.enableXMTP(XMTP_KEY_HASH_1, "");

        assertTrue(ext.isXMTPEnabled(agent1));
        assertEq(ext.getXMTPEndpoint(agent1), "");
    }
}
