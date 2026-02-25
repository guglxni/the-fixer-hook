// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixerRegistryStorage} from "../storage/FixerRegistryStorage.sol";

/// @title IAgentRegistry Interface
/// @notice Interface for agent registration, reputation, and referral delegation
/// @dev Implements the Agent Infrastructure Stack:
///      - ERC-8004 (Identity & Trust): Permissionless registration via NFT ownership
///      - x402 (Payments): EIP-3009 transferWithAuthorization for FIX micropayments
///      - XMTP (Communication): On-chain XMTP endpoint directory for agent messaging
///
///      All agents MUST register via ERC-8004 NFT ownership proof.
///      Bonus multipliers are derived from on-chain reputation scores.
///      XMTP endpoints enable wallet-to-wallet messaging between agents.
///
/// Enhancement Coverage:
///   - Agent Infrastructure Stack: ERC-8004 + x402 + XMTP
///   - Referral Marketplace (delegation mechanics)
interface IAgentRegistry {

    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when an agent registers via ERC-8004 NFT ownership proof
    event AgentRegistered(
        address indexed agent,
        uint256 indexed agentId,
        FixerRegistryStorage.AgentPlatform indexed platform
    );

    /// @notice Emitted when an agent is deregistered
    event AgentDeregistered(address indexed agent);

    /// @notice Emitted when an agent's cached reputation is refreshed from ERC-8004
    event AgentReputationRefreshed(
        address indexed agent,
        int128 reputationScore,
        uint16 derivedBonusBps
    );

    /// @notice Emitted when referral performance feedback is submitted to ERC-8004
    event ReferralFeedbackSubmitted(
        uint256 indexed agentId,
        int128 value,
        bytes32 tag1
    );

    /// @notice Emitted when a referral delegation is created
    event ReferralDelegated(address indexed delegator, address indexed delegate);

    /// @notice Emitted when a referral delegation is revoked
    event ReferralDelegationRevoked(address indexed delegator, address indexed delegate);

    /// @notice Emitted when ERC-8004 registry addresses are updated
    event ERC8004RegistriesUpdated(
        address identityRegistry,
        address reputationRegistry,
        address validationRegistry
    );

    /// @notice Emitted when reputation cache TTL is updated
    event ReputationCacheTTLUpdated(uint64 oldTTL, uint64 newTTL);

    /// @notice Emitted when an agent enables or updates XMTP endpoint
    event XMTPEndpointUpdated(
        address indexed agent,
        bytes32 publicKeyHash,
        string endpointUri
    );

    /// @notice Emitted when an agent disables XMTP
    event XMTPDisabled(address indexed agent);

    // ========================================================================
    // ERRORS
    // ========================================================================

    /// @notice Thrown when trying to register an already-registered agent
    error AgentAlreadyRegistered();

    /// @notice Thrown when querying a non-existent agent
    error AgentNotRegistered();

    /// @notice Thrown when the agent wallet address is zero
    error InvalidAgentAddress();

    /// @notice Thrown when trying to delegate to yourself
    error CannotDelegateToSelf();

    /// @notice Thrown when delegation already exists
    error DelegationAlreadyExists();

    /// @notice Thrown when delegation does not exist
    error DelegationNotFound();

    /// @notice Thrown when ERC-8004 registry addresses are not configured
    error ERC8004RegistryNotConfigured();

    /// @notice Thrown when caller does not own the ERC-8004 agent NFT
    error InvalidAgentIdOwnership();

    /// @notice Thrown when caller's wallet does not match ERC-8004 agentWallet field
    error AgentWalletMismatch();

    /// @notice Thrown when the ERC-8004 agent ID is already registered to another wallet
    error AgentIdAlreadyRegistered();

    /// @notice Thrown when the agent's validation score is below the minimum threshold
    error MinimumValidationScoreNotMet();

    /// @notice Thrown when reputation cache TTL is out of allowed range
    error InvalidCacheTTL();

    /// @notice Thrown when XMTP endpoint URI exceeds maximum length
    error XMTPEndpointTooLong();

    /// @notice Thrown when XMTP public key hash is zero
    error XMTPInvalidPublicKey();

    /// @notice Thrown when agent XMTP is not enabled
    error XMTPNotEnabled();

    // ========================================================================
    // AGENT REGISTRATION (ERC-8004 — Permissionless)
    // ========================================================================

    /// @notice Register as an agent via ERC-8004 NFT ownership proof (permissionless)
    /// @dev Verifies caller owns the ERC-8004 Identity NFT and is the registered agentWallet.
    ///      No owner/admin approval needed — identity is cryptographically verified on-chain.
    ///      Auto-refreshes reputation from ERC-8004 Reputation Registry after registration.
    /// @param agentId The ERC-8004 NFT token ID owned by the caller
    /// @param platform Which AI platform the agent runs on
    function registerAgent(
        uint256 agentId,
        FixerRegistryStorage.AgentPlatform platform
    ) external;

    /// @notice Deregister an AI agent
    /// @param agent The agent's wallet address to remove
    function deregisterAgent(address agent) external;

    // ========================================================================
    // REPUTATION (ERC-8004)
    // ========================================================================

    /// @notice Refresh an agent's cached reputation from ERC-8004 Reputation Registry
    /// @dev Permissionless — anyone can trigger a refresh for any agent (reads public data)
    /// @param agent The agent's wallet address
    function refreshAgentReputation(address agent) external;

    /// @notice Submit referral performance feedback to ERC-8004 Reputation Registry
    /// @dev Only callable by owner or authorized hooks. Wrapped in try/catch internally.
    /// @param agentId The ERC-8004 agent NFT token ID
    /// @param score The feedback score (signed fixed-point)
    function submitReferralFeedback(uint256 agentId, int128 score) external;

    // ========================================================================
    // REFERRAL DELEGATION (Marketplace)
    // ========================================================================

    /// @notice Delegate referral rights to another address
    /// @dev Allows delegate to use delegator's tier for referrals.
    /// @param delegate The address receiving delegation rights
    function delegateReferral(address delegate) external;

    /// @notice Revoke a referral delegation
    /// @param delegate The address losing delegation rights
    function revokeDelegation(address delegate) external;

    // ========================================================================
    // ADMIN
    // ========================================================================

    /// @notice Set the ERC-8004 registry addresses
    /// @param identity ERC-8004 Identity Registry address
    /// @param reputation ERC-8004 Reputation Registry address
    /// @param validation ERC-8004 Validation Registry address
    function setERC8004Registries(
        address identity,
        address reputation,
        address validation
    ) external;

    /// @notice Set the reputation cache TTL (time-to-live)
    /// @param ttl Cache duration in seconds (min 600, max 86400)
    function setReputationCacheTTL(uint64 ttl) external;

    // ========================================================================
    // XMTP COMMUNICATION (Agent Infrastructure Stack)
    // ========================================================================

    /// @notice Enable XMTP communication and set endpoint for the calling agent
    /// @dev Only registered agents can enable XMTP. Stores public key hash and endpoint URI
    ///      on-chain so other agents can discover XMTP-reachable peers.
    /// @param publicKeyHash keccak256 hash of the agent's XMTP installation public key
    /// @param endpointUri XMTP endpoint URI (e.g., "xmtp://0x.../inbox") — max 256 chars
    function enableXMTP(bytes32 publicKeyHash, string calldata endpointUri) external;

    /// @notice Disable XMTP communication for the calling agent
    function disableXMTP() external;

    /// @notice Update XMTP endpoint URI for an already-enabled agent
    /// @param endpointUri New XMTP endpoint URI
    function updateXMTPEndpoint(string calldata endpointUri) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if an address is a registered agent
    /// @param agent The address to check
    /// @return Whether the agent is registered
    function isRegisteredAgent(address agent) external view returns (bool);

    /// @notice Check if an agent is ERC-8004 verified
    /// @param agent The address to check
    /// @return Whether the agent has an ERC-8004 identity
    function isVerifiedAgent(address agent) external view returns (bool);

    /// @notice Get the reputation-derived bonus multiplier for an agent
    /// @param agent The agent's address
    /// @return bonusBps The bonus multiplier in basis points (derived from ERC-8004 reputation)
    function getAgentMultiplierBonus(address agent) external view returns (uint16 bonusBps);

    /// @notice Get the full agent profile
    /// @param agent The agent's address
    /// @return profile The agent's on-chain profile
    function getAgentProfile(address agent)
        external
        view
        returns (FixerRegistryStorage.AgentProfile memory profile);

    /// @notice Check if a delegation exists
    /// @param delegator The address that delegated
    /// @param delegate The address that received delegation
    /// @return Whether the delegation is active
    function isDelegated(address delegator, address delegate) external view returns (bool);

    /// @notice Get the total number of registered agents
    /// @return count Total registered agents
    function getTotalAgents() external view returns (uint64 count);

    /// @notice Get the number of agents per platform
    /// @param platform The platform to query
    /// @return count Number of agents on that platform
    function getAgentCountByPlatform(FixerRegistryStorage.AgentPlatform platform)
        external
        view
        returns (uint64 count);

    /// @notice Get the reputation-derived bonus for an agent
    /// @param agent The agent's wallet address
    /// @return bonusBps The reputation-derived bonus in basis points
    function getReputationBonus(address agent) external view returns (uint16 bonusBps);

    /// @notice Get the ERC-8004 configuration
    /// @return identity Identity Registry address
    /// @return reputation Reputation Registry address
    /// @return validation Validation Registry address
    /// @return cacheTTL Reputation cache TTL in seconds
    /// @return agentCount Number of registered agents
    function getERC8004Config()
        external
        view
        returns (
            address identity,
            address reputation,
            address validation,
            uint64 cacheTTL,
            uint64 agentCount
        );

    // ========================================================================
    // XMTP VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if an agent has XMTP enabled
    /// @param agent The agent's address
    /// @return Whether XMTP is enabled for this agent
    function isXMTPEnabled(address agent) external view returns (bool);

    /// @notice Get the XMTP public key hash for an agent
    /// @param agent The agent's address
    /// @return publicKeyHash The keccak256 hash of the agent's XMTP installation key
    function getXMTPPublicKeyHash(address agent) external view returns (bytes32 publicKeyHash);

    /// @notice Get the XMTP endpoint URI for an agent
    /// @param agent The agent's address
    /// @return endpointUri The XMTP endpoint URI
    function getXMTPEndpoint(address agent) external view returns (string memory endpointUri);

    /// @notice Get the count of XMTP-enabled agents
    /// @return count Number of agents with XMTP enabled
    function getXMTPEnabledCount() external view returns (uint64 count);
}
