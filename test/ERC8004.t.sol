// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";
import {IAgentRegistry} from "../src/interfaces/IAgentRegistry.sol";
import {IFixerRegistryFull} from "./helpers/IFixerRegistryFull.sol";
import {ERC8004Constants} from "../src/types/AgentTypes.sol";
import {IERC8004IdentityRegistry} from "../src/interfaces/IERC8004IdentityRegistry.sol";
import {IERC8004ReputationRegistry} from "../src/interfaces/IERC8004ReputationRegistry.sol";
import {IERC8004ValidationRegistry} from "../src/interfaces/IERC8004ValidationRegistry.sol";

// ============================================================================
// MOCK CONTRACTS
// ============================================================================

/// @notice Mock ERC-8004 Identity Registry for testing
contract MockIdentityRegistry is IERC8004IdentityRegistry {
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

/// @notice Mock ERC-8004 Reputation Registry for testing
contract MockReputationRegistry is IERC8004ReputationRegistry {
    mapping(uint256 => int128) public scores;
    mapping(uint256 => uint8) public scoreDecimals;
    bool public shouldRevert;

    // Track feedback submissions
    uint256 public feedbackCount;
    uint256 public lastFeedbackAgentId;
    int128 public lastFeedbackValue;

    function setScore(uint256 agentId, int128 score, uint8 decimals_) external {
        scores[agentId] = score;
        scoreDecimals[agentId] = decimals_;
    }

    function setShouldRevert(bool revert_) external {
        shouldRevert = revert_;
    }

    function getSummary(
        uint256 agentId,
        address[] calldata,
        bytes32,
        bytes32
    ) external view returns (uint256 count, int128 summaryValue, uint8 decimals_) {
        if (shouldRevert) revert("MockReputationRegistry: forced revert");
        return (1, scores[agentId], scoreDecimals[agentId]);
    }

    function readFeedback(uint256, address, uint256) external pure returns (int128, uint8, bytes32, bytes32, bool) {
        return (0, 0, bytes32(0), bytes32(0), false);
    }

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8,
        bytes32,
        bytes32,
        bytes32,
        string calldata,
        bytes32
    ) external {
        if (shouldRevert) revert("MockReputationRegistry: forced revert");
        feedbackCount += 1;
        lastFeedbackAgentId = agentId;
        lastFeedbackValue = value;
    }
}

/// @notice Mock ERC-8004 Validation Registry for testing
contract MockValidationRegistry is IERC8004ValidationRegistry {
    mapping(uint256 => uint8) public validationScores;

    function setScore(uint256 agentId, uint8 score) external {
        validationScores[agentId] = score;
    }

    function getSummary(
        uint256 agentId,
        address[] calldata,
        bytes32
    ) external view returns (uint256 count, uint8 averageResponse) {
        return (1, validationScores[agentId]);
    }
}

// ============================================================================
// TEST: ERC-8004 PERMISSIONLESS REGISTRATION
// ============================================================================

contract ERC8004RegistrationTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");

    uint256 public constant AGENT_ID_1 = 42;
    uint256 public constant AGENT_ID_2 = 99;

    function setUp() public {
        // Deploy mock registries
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();

        // Deploy registry proxy
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        // Configure ERC-8004 registries via reinitializeV4
        // Need to do this via upgradeToAndCall or direct call
        // Since reinitializer(4) means we need to call it directly
        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        // Set up identity for agent1
        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);

        // Set up identity for agent2
        identityRegistry.setOwner(AGENT_ID_2, agent2);
        identityRegistry.setAgentWallet(AGENT_ID_2, agent2);
    }

    function test_registerAgent_success() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        assertTrue(ext.isRegisteredAgent(agent1));
        assertTrue(ext.isVerifiedAgent(agent1));

        FixerRegistryStorage.AgentProfile memory profile = ext.getAgentProfile(agent1);
        assertEq(profile.wallet, agent1);
        assertEq(profile.erc8004AgentId, AGENT_ID_1);
        assertTrue(profile.verified);
        assertEq(uint8(profile.platform), uint8(FixerRegistryStorage.AgentPlatform.OpenClaw));
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

    function test_registerAgent_incrementsCounters() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        assertEq(ext.getTotalAgents(), 1);

        (,,,, uint64 erc8004Count) = ext.getERC8004Config();
        assertEq(erc8004Count, 1);

        assertEq(
            ext.getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform.OpenClaw),
            1
        );
    }

    function test_registerAgent_multipleAgents() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        vm.prank(agent2);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.Moltbook);

        assertEq(ext.getTotalAgents(), 2);

        (,,,, uint64 erc8004Count) = ext.getERC8004Config();
        assertEq(erc8004Count, 2);
    }

    function test_registerAgent_reverts_notNFTOwner() public {
        // agent2 tries to register with agent1's NFT
        vm.prank(agent2);
        vm.expectRevert(IAgentRegistry.InvalidAgentIdOwnership.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_reverts_walletMismatch() public {
        // Set up: agent1 owns the NFT but agentWallet is different
        identityRegistry.setAgentWallet(AGENT_ID_1, agent2);

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.AgentWalletMismatch.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_reverts_agentIdAlreadyRegistered() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        // agent2 tries to register the same agentId (which should be impossible in practice
        // since they'd need a different NFT, but we test the guard)
        identityRegistry.setOwner(AGENT_ID_1, agent2);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent2);

        vm.prank(agent2);
        vm.expectRevert(IAgentRegistry.AgentIdAlreadyRegistered.selector);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_reverts_walletAlreadyRegistered() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        // agent1 tries to register again with a different agentId
        identityRegistry.setOwner(AGENT_ID_2, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_2, agent1);

        vm.prank(agent1);
        vm.expectRevert(IAgentRegistry.AgentAlreadyRegistered.selector);
        ext.registerAgent(AGENT_ID_2, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_registerAgent_reverts_registryNotConfigured() public {
        // Deploy a fresh registry without ERC-8004 configuration
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

    function test_registerAgent_reverts_whenAgentsPaused() public {
        vm.prank(securityCouncil);
        registry.pauseAgents();

        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("AgentSystemPaused()"));
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_deregisterAgent_cleansUpERC8004State() public {
        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);

        (,,,, uint64 countBefore) = ext.getERC8004Config();
        assertEq(countBefore, 1);

        vm.prank(owner);
        ext.deregisterAgent(agent1);

        assertFalse(ext.isRegisteredAgent(agent1));
        assertFalse(ext.isVerifiedAgent(agent1));

        (,,,, uint64 countAfter) = ext.getERC8004Config();
        assertEq(countAfter, 0);
    }
}

// ============================================================================
// TEST: ERC-8004 REPUTATION REFRESH
// ============================================================================

contract ERC8004ReputationTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public agent1 = makeAddr("agent1");
    address public keeper = makeAddr("keeper");

    uint256 public constant AGENT_ID_1 = 42;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);

        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_refreshAgentReputation_lowScore() public {
        reputationRegistry.setScore(AGENT_ID_1, 15, 0); // Score 15 = Low tier

        vm.prank(keeper);
        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_LOW);

        FixerRegistryStorage.AgentProfile memory profile = ext.getAgentProfile(agent1);
        assertEq(profile.cachedReputationScore, 15);
        assertEq(profile.cachedReputationDecimals, 0);
        assertTrue(profile.lastReputationUpdate > 0);
    }

    function test_refreshAgentReputation_mediumScore() public {
        reputationRegistry.setScore(AGENT_ID_1, 50, 0); // Score 50 = Medium tier

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_MEDIUM);
    }

    function test_refreshAgentReputation_highScore() public {
        reputationRegistry.setScore(AGENT_ID_1, 75, 0); // Score 75 = High tier

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_HIGH);
    }

    function test_refreshAgentReputation_eliteScore() public {
        reputationRegistry.setScore(AGENT_ID_1, 95, 0); // Score 95 = Elite tier

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);
    }

    function test_refreshAgentReputation_withDecimals() public {
        // Score 75.5 with 1 decimal = 755 / 10 = 75 = High tier
        reputationRegistry.setScore(AGENT_ID_1, 755, 1);

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_HIGH);
    }

    function test_refreshAgentReputation_negativeScore() public {
        reputationRegistry.setScore(AGENT_ID_1, -50, 0); // Negative score

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_NONE);
    }

    function test_refreshAgentReputation_zeroScore() public {
        reputationRegistry.setScore(AGENT_ID_1, 0, 0);

        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_NONE);
    }

    function test_refreshAgentReputation_emitsEvent() public {
        reputationRegistry.setScore(AGENT_ID_1, 85, 0);

        vm.expectEmit(true, false, false, true);
        emit IAgentRegistry.AgentReputationRefreshed(agent1, 85, ERC8004Constants.BONUS_ELITE);

        ext.refreshAgentReputation(agent1);
    }

    function test_refreshAgentReputation_anyoneCanCall() public {
        reputationRegistry.setScore(AGENT_ID_1, 50, 0);

        // Keeper (random address) can refresh anyone's reputation
        vm.prank(keeper);
        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_MEDIUM);
    }

    function test_refreshAgentReputation_retainsCacheOnRevert() public {
        // First: set a valid score
        reputationRegistry.setScore(AGENT_ID_1, 85, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);

        // Now make the registry revert
        reputationRegistry.setShouldRevert(true);

        // Refresh should silently fail and retain cached score
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);
    }

    function test_refreshAgentReputation_reverts_notRegistered() public {
        vm.expectRevert(IAgentRegistry.AgentNotRegistered.selector);
        ext.refreshAgentReputation(makeAddr("nobody"));
    }

    function test_refreshAgentReputation_boundaryScores() public {
        // Test exact boundary values

        // Score 1 = Low
        reputationRegistry.setScore(AGENT_ID_1, 1, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_LOW);

        // Score 30 = Low
        reputationRegistry.setScore(AGENT_ID_1, 30, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_LOW);

        // Score 31 = Medium
        reputationRegistry.setScore(AGENT_ID_1, 31, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_MEDIUM);

        // Score 60 = Medium
        reputationRegistry.setScore(AGENT_ID_1, 60, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_MEDIUM);

        // Score 61 = High
        reputationRegistry.setScore(AGENT_ID_1, 61, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_HIGH);

        // Score 80 = High
        reputationRegistry.setScore(AGENT_ID_1, 80, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_HIGH);

        // Score 81 = Elite
        reputationRegistry.setScore(AGENT_ID_1, 81, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);

        // Score 100 = Elite
        reputationRegistry.setScore(AGENT_ID_1, 100, 0);
        ext.refreshAgentReputation(agent1);
        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);
    }
}

// ============================================================================
// TEST: REPUTATION-BASED REWARD CALCULATION
// ============================================================================

contract ERC8004RewardTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public agent1 = makeAddr("agent1");
    address public swapper = makeAddr("swapper");
    address public hookAddr;

    uint256 public constant AGENT_ID_1 = 42;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        // Register a mock hook
        hookAddr = makeAddr("hook");
        bytes32 poolId = keccak256("pool1");
        vm.prank(owner);
        registry.registerHook(hookAddr, poolId);

        // Register ERC-8004 agent with elite reputation
        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);
        reputationRegistry.setScore(AGENT_ID_1, 85, 0); // Elite = 5000 BPS bonus

        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function test_rewardWithERC8004Bonus() public {
        uint256 volume = 10_000e18;
        bytes32 poolId = keccak256("pool1");

        // ERC-8004 agent with Elite bonus (50%)
        vm.prank(hookAddr);
        uint256 reward = registry.recordReferral(agent1, swapper, volume, poolId);

        // reward should include the elite bonus (50% on top of gross)
        assertTrue(reward > 0);
    }

    function test_agentBonusHigherThanNonAgent() public {
        uint256 volume = 10_000e18;
        bytes32 poolId = keccak256("pool1");
        bytes32 poolId2 = keccak256("pool2");

        // Register second hook for non-agent referral
        address hookAddr2 = makeAddr("hook2");
        vm.prank(owner);
        registry.registerHook(hookAddr2, poolId2);

        // ERC-8004 agent (elite reputation = 50% bonus)
        vm.prank(hookAddr);
        uint256 agentReward = registry.recordReferral(agent1, swapper, volume, poolId);

        // Regular referrer (no agent bonus)
        address regularReferrer = makeAddr("regularReferrer");
        vm.prank(hookAddr2);
        uint256 normalReward = registry.recordReferral(regularReferrer, swapper, volume, poolId2);

        // Agent should earn more due to reputation bonus
        assertTrue(agentReward > normalReward);
    }

    function test_staleCache_degradesToGraceBonus() public {
        uint256 volume = 10_000e18;
        bytes32 poolId = keccak256("pool1");

        // Fast forward past the cache TTL (default 1 hour)
        vm.warp(block.timestamp + 3601);

        vm.prank(hookAddr);
        uint256 staleReward = registry.recordReferral(agent1, swapper, volume, poolId);

        // Refresh the reputation to get fresh cache
        reputationRegistry.setScore(AGENT_ID_1, 85, 0);
        ext.refreshAgentReputation(agent1);

        // Now record another referral with fresh cache
        vm.prank(hookAddr);
        uint256 freshReward = registry.recordReferral(agent1, swapper, volume, poolId);

        // Fresh cache should give elite bonus (50%), stale gives grace bonus (5%)
        // freshReward should be higher
        assertTrue(freshReward > staleReward);
    }

    function test_noBonus_forNonAgent() public {
        address regularReferrer = makeAddr("regularReferrer");
        uint256 volume = 10_000e18;
        bytes32 poolId = keccak256("pool1");

        vm.prank(hookAddr);
        uint256 reward = registry.recordReferral(regularReferrer, swapper, volume, poolId);

        // Regular referrer gets no agent bonus
        assertTrue(reward > 0);
    }
}

// ============================================================================
// TEST: ERC-8004 FEEDBACK SUBMISSION
// ============================================================================

contract ERC8004FeedbackTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");

    uint256 public constant AGENT_ID_1 = 42;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));
    }

    function test_submitReferralFeedback_asOwner() public {
        int128 score = 85;

        vm.prank(owner);
        ext.submitReferralFeedback(AGENT_ID_1, score);

        assertEq(reputationRegistry.feedbackCount(), 1);
        assertEq(reputationRegistry.lastFeedbackAgentId(), AGENT_ID_1);
        assertEq(reputationRegistry.lastFeedbackValue(), score);
    }

    function test_submitReferralFeedback_asAuthorizedHook() public {
        address hookAddr = makeAddr("hook");
        vm.prank(owner);
        registry.registerHook(hookAddr, keccak256("pool1"));

        vm.prank(hookAddr);
        ext.submitReferralFeedback(AGENT_ID_1, 50);

        assertEq(reputationRegistry.feedbackCount(), 1);
    }

    function test_submitReferralFeedback_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAgentRegistry.ReferralFeedbackSubmitted(
            AGENT_ID_1,
            85,
            ERC8004Constants.TAG_REFERRAL
        );

        vm.prank(owner);
        ext.submitReferralFeedback(AGENT_ID_1, 85);
    }

    function test_submitReferralFeedback_reverts_unauthorized() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedHook()"));
        ext.submitReferralFeedback(AGENT_ID_1, 85);
    }

    function test_submitReferralFeedback_reverts_noReputationRegistry() public {
        // Deploy fresh registry without reputation registry
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

        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.ERC8004RegistryNotConfigured.selector);
        IFixerRegistryFull(address(proxy2)).submitReferralFeedback(AGENT_ID_1, 85);
    }

    function test_submitReferralFeedback_silentlyFailsOnRevert() public {
        reputationRegistry.setShouldRevert(true);

        // Should NOT revert — the try/catch should swallow the error
        vm.prank(owner);
        ext.submitReferralFeedback(AGENT_ID_1, 85);

        assertEq(reputationRegistry.feedbackCount(), 0);
    }
}

// ============================================================================
// TEST: ERC-8004 ADMIN FUNCTIONS
// ============================================================================

contract ERC8004AdminTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;

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
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        registry.reinitializeV4(address(1), address(2), address(3));

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));
    }

    function test_setERC8004Registries() public {
        address newIdentity = makeAddr("newIdentity");
        address newReputation = makeAddr("newReputation");
        address newValidation = makeAddr("newValidation");

        vm.expectEmit(false, false, false, true);
        emit IAgentRegistry.ERC8004RegistriesUpdated(newIdentity, newReputation, newValidation);

        vm.prank(owner);
        ext.setERC8004Registries(newIdentity, newReputation, newValidation);

        (address id, address rep, address val,,) = ext.getERC8004Config();
        assertEq(id, newIdentity);
        assertEq(rep, newReputation);
        assertEq(val, newValidation);
    }

    function test_setERC8004Registries_reverts_notOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        ext.setERC8004Registries(address(1), address(2), address(3));
    }

    function test_setReputationCacheTTL() public {
        uint64 newTTL = 7200; // 2 hours

        vm.prank(owner);
        ext.setReputationCacheTTL(newTTL);

        (,,, uint64 cacheTTL,) = ext.getERC8004Config();
        assertEq(cacheTTL, newTTL);
    }

    function test_setReputationCacheTTL_emitsEvent() public {
        uint64 newTTL = 7200;

        vm.expectEmit(false, false, false, true);
        emit IAgentRegistry.ReputationCacheTTLUpdated(ERC8004Constants.DEFAULT_CACHE_TTL, newTTL);

        vm.prank(owner);
        ext.setReputationCacheTTL(newTTL);
    }

    function test_setReputationCacheTTL_reverts_tooLow() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.InvalidCacheTTL.selector);
        ext.setReputationCacheTTL(599); // Below MIN_CACHE_TTL (600)
    }

    function test_setReputationCacheTTL_reverts_tooHigh() public {
        vm.prank(owner);
        vm.expectRevert(IAgentRegistry.InvalidCacheTTL.selector);
        ext.setReputationCacheTTL(86401); // Above MAX_CACHE_TTL (86400)
    }

    function test_setReputationCacheTTL_boundary_min() public {
        vm.prank(owner);
        ext.setReputationCacheTTL(600); // Exactly MIN_CACHE_TTL

        (,,, uint64 cacheTTL,) = ext.getERC8004Config();
        assertEq(cacheTTL, 600);
    }

    function test_setReputationCacheTTL_boundary_max() public {
        vm.prank(owner);
        ext.setReputationCacheTTL(86400); // Exactly MAX_CACHE_TTL

        (,,, uint64 cacheTTL,) = ext.getERC8004Config();
        assertEq(cacheTTL, 86400);
    }

    function test_setReputationCacheTTL_reverts_notOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        ext.setReputationCacheTTL(7200);
    }

    function test_getERC8004Config() public view {
        (
            address identity,
            address reputation,
            address validation,
            uint64 cacheTTL,
            uint64 agentCount
        ) = ext.getERC8004Config();

        assertEq(identity, address(1));
        assertEq(reputation, address(2));
        assertEq(validation, address(3));
        assertEq(cacheTTL, ERC8004Constants.DEFAULT_CACHE_TTL);
        assertEq(agentCount, 0);
    }
}

// ============================================================================
// TEST: FUZZ — REPUTATION BONUS COMPUTATION
// ============================================================================

contract ERC8004FuzzTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;

    address public owner = makeAddr("owner");
    address public securityCouncil = makeAddr("securityCouncil");
    address public governance = makeAddr("governance");
    address public agent1 = makeAddr("agent1");

    uint256 public constant AGENT_ID_1 = 42;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (owner, securityCouncil, governance)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        registry.reinitializeV4(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry)
        );

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));

        identityRegistry.setOwner(AGENT_ID_1, agent1);
        identityRegistry.setAgentWallet(AGENT_ID_1, agent1);

        vm.prank(agent1);
        ext.registerAgent(AGENT_ID_1, FixerRegistryStorage.AgentPlatform.OpenClaw);
    }

    function testFuzz_reputationBonus_validBpsRange(int128 score, uint8 decimals_) public {
        // Bound decimals to reasonable range (0-18)
        decimals_ = uint8(bound(uint256(decimals_), 0, 18));

        reputationRegistry.setScore(AGENT_ID_1, score, decimals_);

        // Should never revert
        ext.refreshAgentReputation(agent1);

        uint16 bonus = ext.getReputationBonus(agent1);

        // Bonus must be one of the valid tier values
        assertTrue(
            bonus == ERC8004Constants.BONUS_NONE ||
            bonus == ERC8004Constants.BONUS_LOW ||
            bonus == ERC8004Constants.BONUS_MEDIUM ||
            bonus == ERC8004Constants.BONUS_HIGH ||
            bonus == ERC8004Constants.BONUS_ELITE,
            "Bonus must be a valid tier value"
        );
    }

    function testFuzz_reputationBonus_negativeScoreAlwaysZero(int128 score) public {
        // Only test negative scores
        vm.assume(score < 0);

        reputationRegistry.setScore(AGENT_ID_1, score, 0);
        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_NONE);
    }

    function testFuzz_reputationBonus_highDecimalsWithLargeScore(uint8 decimals_) public {
        // Bound decimals to 0-18
        decimals_ = uint8(bound(uint256(decimals_), 0, 18));

        // Score that normalizes to 85 regardless of decimals
        int128 score = int128(int256(85 * (10 ** uint256(decimals_))));

        reputationRegistry.setScore(AGENT_ID_1, score, decimals_);
        ext.refreshAgentReputation(agent1);

        assertEq(ext.getReputationBonus(agent1), ERC8004Constants.BONUS_ELITE);
    }
}

// ============================================================================
// TEST: REINITIALIZEV4
// ============================================================================

contract ERC8004ReinitializeTest is Test {
    FixerRegistryUpgradeable public registry;
    IFixerRegistryFull public ext;

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
        registry = FixerRegistryUpgradeable(payable(address(proxy)));

        FixerRegistryExtension extensionImpl = new FixerRegistryExtension();
        vm.prank(owner);
        registry.setExtension(address(extensionImpl));
        ext = IFixerRegistryFull(address(proxy));
    }

    function test_reinitializeV4_setsRegistries() public {
        address identity = makeAddr("identity");
        address reputation = makeAddr("reputation");
        address validation = makeAddr("validation");

        registry.reinitializeV4(identity, reputation, validation);

        (
            address id,
            address rep,
            address val,
            uint64 cacheTTL,
        ) = ext.getERC8004Config();

        assertEq(id, identity);
        assertEq(rep, reputation);
        assertEq(val, validation);
        assertEq(cacheTTL, ERC8004Constants.DEFAULT_CACHE_TTL);
    }

    function test_reinitializeV4_cannotCallTwice() public {
        registry.reinitializeV4(address(1), address(2), address(3));

        vm.expectRevert();
        registry.reinitializeV4(address(4), address(5), address(6));
    }

    function test_version_is_v250() public view {
        assertEq(registry.VERSION(), 2_006_000);
    }
}
