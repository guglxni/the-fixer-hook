// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// OpenZeppelin Upgradeable (same inheritance chain as core — required for
// matching ERC-7201 storage access when called via DELEGATECALL)
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

// Internal
import {FixerRegistryStorage} from "./storage/FixerRegistryStorage.sol";
import {EmergencyModule} from "./modules/EmergencyModule.sol";
import {ERC8004Constants, XMTPConstants} from "./types/AgentTypes.sol";
import {FixerLib} from "./libraries/FixerLib.sol";

// Interfaces
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerRegistryExtension
/// @author Aaryan Guglani
/// @notice Extension module for ERC-8004 agent operations and EIP-3009 authorization
/// @dev Part of the Reactive Modular Architecture that splits FixerRegistryUpgradeable
///      into two contracts to stay under the EIP-170 contract size limit (24,576 bytes):
///
///      ┌─────────────────────────────────────────────────────────────┐
///      │  ERC1967Proxy                                              │
///      │    │                                                       │
///      │    ▼                                                       │
///      │  FixerRegistryUpgradeable (Core)                           │
///      │    ├── Referrals, ERC20, Tiers, Emergency, Hooks, Admin    │
///      │    └── fallback() ──delegatecall──▶ FixerRegistryExtension │
///      │                                      ├── ERC-8004 Agents   │
///      │                                      ├── Delegation        │
///      │                                      ├── Reputation        │
///      │                                      └── EIP-3009 Auth     │
///      └─────────────────────────────────────────────────────────────┘
///
///      Storage Compatibility:
///      - Uses identical ERC-7201 namespaced storage (FixerRegistryStorage)
///      - Inherits same OZ upgradeable bases for access to _mint, _transfer, owner()
///      - All function execution happens in the proxy's storage context via DELEGATECALL
///
///      This pattern is inspired by Reactive Network's modular architecture where
///      functionality is distributed across coordinating contracts that share state
///      via events and callbacks. Here, the coordination is synchronous via delegatecall.
contract FixerRegistryExtension is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    EmergencyModule,
    IAgentRegistry
{
    using FixerRegistryStorage for *;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice EIP-3009 typehash for transferWithAuthorization
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    /// @notice EIP-3009: Authorization nonce already consumed
    error AuthorizationAlreadyUsed();

    /// @notice Caller is not an authorized hook or owner
    error UnauthorizedHook();

    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice EIP-3009: Emitted when a transfer authorization is used
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    // ========================================================================
    // CONSTRUCTOR (disable initializers on implementation)
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ========================================================================
    // AGENT REGISTRY (ERC-8004 + x402 + XMTP)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    /// @dev Validates ERC-8004 NFT ownership via FixerLib.validateAgent (DELEGATECALL).
    ///      Auto-refreshes reputation from ERC-8004 Reputation Registry after registration.
    function registerAgent(
        uint256 agentId,
        FixerRegistryStorage.AgentPlatform platform
    ) external whenNotPausedAgents nonReentrant {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        // Verify ERC-8004 registries are configured
        if (s.identityRegistry == address(0)) revert ERC8004RegistryNotConfigured();

        // Verify agent ID not already registered
        if (s.agentIdToWallet[agentId] != address(0)) revert AgentIdAlreadyRegistered();

        // Verify wallet not already taken
        if (s.agentProfiles[msg.sender].wallet != address(0)) revert AgentAlreadyRegistered();

        // Validate ownership + optional validation score via external library
        FixerLib.validateAgent(s.identityRegistry, s.validationRegistry, agentId, msg.sender);

        // Create agent profile
        s.agentProfiles[msg.sender] = FixerRegistryStorage.AgentProfile({
            wallet: msg.sender,
            x402Identity: bytes32(0),
            registeredAt: uint64(block.timestamp),
            platform: platform,
            x402Volume: 0,
            verified: true,
            bonusMultiplierBps: 0,
            erc8004AgentId: agentId,
            cachedReputationScore: 0,
            cachedReputationDecimals: 0,
            derivedBonusBps: 0,
            lastReputationUpdate: 0,
            xmtpEnabled: false,
            xmtpPublicKeyHash: bytes32(0),
            xmtpEndpointUri: ""
        });

        // Register reverse mapping
        s.agentIdToWallet[agentId] = msg.sender;
        s.totalAgents += 1;
        s.erc8004AgentCount += 1;
        s.agentPlatformCount[uint8(platform)] += 1;

        emit AgentRegistered(msg.sender, agentId, platform);

        // Auto-refresh reputation if reputation registry is available
        if (s.reputationRegistry != address(0)) {
            _refreshReputationInternal(s, msg.sender);
        }
    }

    /// @inheritdoc IAgentRegistry
    function deregisterAgent(address agent) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet == address(0)) revert AgentNotRegistered();

        FixerRegistryStorage.AgentPlatform platform = s.agentProfiles[agent].platform;

        // Clean up ERC-8004 reverse mapping
        uint256 erc8004Id = s.agentProfiles[agent].erc8004AgentId;
        if (erc8004Id != 0) {
            delete s.agentIdToWallet[erc8004Id];
            s.erc8004AgentCount -= 1;
        }

        // Clean up XMTP counter
        if (s.agentProfiles[agent].xmtpEnabled) {
            s.xmtpEnabledCount -= 1;
        }

        delete s.agentProfiles[agent];

        s.totalAgents -= 1;
        s.agentPlatformCount[uint8(platform)] -= 1;

        emit AgentDeregistered(agent);
    }

    // ========================================================================
    // REFERRAL DELEGATION (Marketplace)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function delegateReferral(address delegate) external {
        if (delegate == msg.sender) revert CannotDelegateToSelf();
        if (delegate == address(0)) revert InvalidAgentAddress();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.referralDelegations[msg.sender][delegate]) revert DelegationAlreadyExists();

        s.referralDelegations[msg.sender][delegate] = true;

        emit ReferralDelegated(msg.sender, delegate);
    }

    /// @inheritdoc IAgentRegistry
    function revokeDelegation(address delegate) external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.referralDelegations[msg.sender][delegate]) revert DelegationNotFound();

        s.referralDelegations[msg.sender][delegate] = false;

        emit ReferralDelegationRevoked(msg.sender, delegate);
    }

    // ========================================================================
    // AGENT VIEW FUNCTIONS
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function isRegisteredAgent(address agent) external view returns (bool) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].wallet != address(0);
    }

    /// @inheritdoc IAgentRegistry
    function isVerifiedAgent(address agent) external view returns (bool) {
        FixerRegistryStorage.AgentProfile storage profile =
            FixerRegistryStorage.getStorage().agentProfiles[agent];
        return profile.wallet != address(0) && profile.erc8004AgentId != 0;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentMultiplierBonus(address agent) external view returns (uint16 bonusBps) {
        FixerRegistryStorage.AgentProfile storage profile =
            FixerRegistryStorage.getStorage().agentProfiles[agent];
        if (profile.wallet != address(0) && profile.erc8004AgentId != 0) {
            return profile.derivedBonusBps;
        }
        return 0;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentProfile(address agent)
        external
        view
        returns (FixerRegistryStorage.AgentProfile memory profile)
    {
        return FixerRegistryStorage.getStorage().agentProfiles[agent];
    }

    /// @inheritdoc IAgentRegistry
    function isDelegated(address delegator, address delegate) external view returns (bool) {
        return FixerRegistryStorage.getStorage().referralDelegations[delegator][delegate];
    }

    /// @inheritdoc IAgentRegistry
    function getTotalAgents() external view returns (uint64 count) {
        return FixerRegistryStorage.getStorage().totalAgents;
    }

    /// @inheritdoc IAgentRegistry
    function getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform platform)
        external
        view
        returns (uint64 count)
    {
        return FixerRegistryStorage.getStorage().agentPlatformCount[uint8(platform)];
    }

    // ========================================================================
    // ERC-8004 REPUTATION
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function refreshAgentReputation(address agent) external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.agentProfiles[agent].wallet == address(0)) revert AgentNotRegistered();
        if (s.agentProfiles[agent].erc8004AgentId == 0) revert ERC8004RegistryNotConfigured();
        if (s.reputationRegistry == address(0)) revert ERC8004RegistryNotConfigured();

        _refreshReputationInternal(s, agent);
    }

    /// @notice Internal reputation refresh implementation
    /// @dev Delegates external call + try/catch to FixerLib. Retains cache on failure.
    function _refreshReputationInternal(
        FixerRegistryStorage.MainStorage storage s,
        address agent
    ) internal {
        FixerRegistryStorage.AgentProfile storage profile = s.agentProfiles[agent];

        (bool success, int128 score, uint8 decimals, uint16 bonusBps) =
            FixerLib.fetchReputation(s.reputationRegistry, profile.erc8004AgentId);

        if (success) {
            profile.cachedReputationScore = score;
            profile.cachedReputationDecimals = decimals;
            profile.lastReputationUpdate = uint64(block.timestamp);
            profile.derivedBonusBps = bonusBps;

            emit AgentReputationRefreshed(agent, score, bonusBps);
        }
    }

    // ========================================================================
    // ERC-8004 FEEDBACK (v2.4)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    /// @dev External call delegated to FixerLib to reduce contract size.
    function submitReferralFeedback(uint256 agentId, int128 score) external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        // Only owner or authorized hooks can submit feedback
        if (msg.sender != owner() && !s.authorizedHooks[msg.sender]) revert UnauthorizedHook();

        if (s.reputationRegistry == address(0)) revert ERC8004RegistryNotConfigured();

        if (FixerLib.sendFeedback(s.reputationRegistry, agentId, score)) {
            emit ReferralFeedbackSubmitted(agentId, score, ERC8004Constants.TAG_REFERRAL);
        }
    }

    // ========================================================================
    // ERC-8004 ADMIN
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function setERC8004Registries(
        address identity,
        address reputation,
        address validation
    ) external onlyOwner {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        s.identityRegistry = identity;
        s.reputationRegistry = reputation;
        s.validationRegistry = validation;

        emit ERC8004RegistriesUpdated(identity, reputation, validation);
    }

    /// @inheritdoc IAgentRegistry
    function setReputationCacheTTL(uint64 ttl) external onlyOwner {
        if (ttl < ERC8004Constants.MIN_CACHE_TTL || ttl > ERC8004Constants.MAX_CACHE_TTL) {
            revert InvalidCacheTTL();
        }

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        uint64 oldTTL = s.reputationCacheTTL;
        s.reputationCacheTTL = ttl;

        emit ReputationCacheTTLUpdated(oldTTL, ttl);
    }

    /// @inheritdoc IAgentRegistry
    function getReputationBonus(address agent) external view returns (uint16 bonusBps) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].derivedBonusBps;
    }

    /// @inheritdoc IAgentRegistry
    function getERC8004Config()
        external
        view
        returns (
            address identity,
            address reputation,
            address validation,
            uint64 cacheTTL,
            uint64 agentCount
        )
    {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        return (
            s.identityRegistry,
            s.reputationRegistry,
            s.validationRegistry,
            s.reputationCacheTTL,
            s.erc8004AgentCount
        );
    }

    // ========================================================================
    // EIP-3009: transferWithAuthorization (FIX as x402 currency)
    // ========================================================================

    /// @notice Execute a transfer with a signed authorization (EIP-3009)
    /// @dev Enables gasless FIX transfers for x402 payment settlements.
    ///      Signature validation delegated to FixerLib to reduce contract size.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Validate timing + signature via external library (DELEGATECALL)
        bytes32 authKey = FixerLib.validateAuth(
            from, to, value, validAfter, validBefore, nonce,
            v, r, s, _domainSeparatorV4(), TRANSFER_WITH_AUTHORIZATION_TYPEHASH
        );

        FixerRegistryStorage.MainStorage storage stor = FixerRegistryStorage.getStorage();
        if (stor.authorizationStates[authKey]) revert AuthorizationAlreadyUsed();

        stor.authorizationStates[authKey] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    /// @notice Check if an authorization nonce has been used
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        bytes32 authKey = keccak256(abi.encodePacked(authorizer, nonce));
        return FixerRegistryStorage.getStorage().authorizationStates[authKey];
    }

    /// @notice Returns the EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ========================================================================
    // XMTP COMMUNICATION (Agent Infrastructure Stack)
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    /// @dev Sets XMTP public key hash and endpoint URI for the calling agent.
    ///      Only registered agents can enable XMTP messaging.
    function enableXMTP(bytes32 publicKeyHash, string calldata endpointUri) external {
        if (publicKeyHash == bytes32(0)) revert XMTPInvalidPublicKey();
        if (bytes(endpointUri).length > XMTPConstants.MAX_ENDPOINT_URI_LENGTH) revert XMTPEndpointTooLong();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.AgentProfile storage profile = s.agentProfiles[msg.sender];
        if (profile.wallet == address(0)) revert AgentNotRegistered();

        bool wasEnabled = profile.xmtpEnabled;

        profile.xmtpEnabled = true;
        profile.xmtpPublicKeyHash = publicKeyHash;
        profile.xmtpEndpointUri = endpointUri;

        if (!wasEnabled) {
            s.xmtpEnabledCount += 1;
        }

        emit XMTPEndpointUpdated(msg.sender, publicKeyHash, endpointUri);
    }

    /// @inheritdoc IAgentRegistry
    function disableXMTP() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.AgentProfile storage profile = s.agentProfiles[msg.sender];
        if (profile.wallet == address(0)) revert AgentNotRegistered();
        if (!profile.xmtpEnabled) revert XMTPNotEnabled();

        profile.xmtpEnabled = false;
        profile.xmtpPublicKeyHash = bytes32(0);
        profile.xmtpEndpointUri = "";

        s.xmtpEnabledCount -= 1;

        emit XMTPDisabled(msg.sender);
    }

    /// @inheritdoc IAgentRegistry
    function updateXMTPEndpoint(string calldata endpointUri) external {
        if (bytes(endpointUri).length > XMTPConstants.MAX_ENDPOINT_URI_LENGTH) revert XMTPEndpointTooLong();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.AgentProfile storage profile = s.agentProfiles[msg.sender];
        if (profile.wallet == address(0)) revert AgentNotRegistered();
        if (!profile.xmtpEnabled) revert XMTPNotEnabled();

        profile.xmtpEndpointUri = endpointUri;

        emit XMTPEndpointUpdated(msg.sender, profile.xmtpPublicKeyHash, endpointUri);
    }

    // ========================================================================
    // XMTP VIEW FUNCTIONS
    // ========================================================================

    /// @inheritdoc IAgentRegistry
    function isXMTPEnabled(address agent) external view returns (bool) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].xmtpEnabled;
    }

    /// @inheritdoc IAgentRegistry
    function getXMTPPublicKeyHash(address agent) external view returns (bytes32 publicKeyHash) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].xmtpPublicKeyHash;
    }

    /// @inheritdoc IAgentRegistry
    function getXMTPEndpoint(address agent) external view returns (string memory endpointUri) {
        return FixerRegistryStorage.getStorage().agentProfiles[agent].xmtpEndpointUri;
    }

    /// @inheritdoc IAgentRegistry
    function getXMTPEnabledCount() external view returns (uint64 count) {
        return FixerRegistryStorage.getStorage().xmtpEnabledCount;
    }
}
