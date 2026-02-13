// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FixerRegistryStorage} from "../storage/FixerRegistryStorage.sol";

/// @title IAgentRegistry Interface
/// @notice Interface for x402-verified agent registration and referral delegation
/// @dev Implemented by FixerRegistryUpgradeable (v2.3+) as part of x402 enhancement.
///      Agents are verified off-chain via x402 payment proofs, then registered on-chain.
///
/// x402 Enhancement Coverage:
///   - Enhancement 2: Agent Referrer Identity via x402
///   - Enhancement 3: x402-Gated Premium Referral Tiers (Diamond/Legendary stubs)
///   - Enhancement 4: Referral Marketplace (delegation mechanics)
interface IAgentRegistry {

    // ========================================================================
    // EVENTS
    // ========================================================================

    /// @notice Emitted when an AI agent is registered on-chain
    event AgentRegistered(
        address indexed agent,
        FixerRegistryStorage.AgentPlatform indexed platform,
        bytes32 x402ProofHash,
        address indexed operator
    );

    /// @notice Emitted when an agent's profile is updated
    event AgentProfileUpdated(address indexed agent, uint16 bonusMultiplierBps, bool verified);

    /// @notice Emitted when an agent's x402 volume is updated (trust signal)
    event AgentX402VolumeUpdated(address indexed agent, uint128 newVolume);

    /// @notice Emitted when a referral delegation is created
    event ReferralDelegated(address indexed delegator, address indexed delegate);

    /// @notice Emitted when a referral delegation is revoked
    event ReferralDelegationRevoked(address indexed delegator, address indexed delegate);

    /// @notice Emitted when an agent is deregistered
    event AgentDeregistered(address indexed agent);

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

    /// @notice Thrown when bonus multiplier exceeds maximum
    error BonusMultiplierTooHigh();

    // ========================================================================
    // AGENT REGISTRATION (Enhancement 2)
    // ========================================================================

    /// @notice Register an AI agent as a verified referrer
    /// @dev Called by owner after off-chain x402 payment verification.
    ///      Flow: Agent pays $1 USDC via x402 → RaaS server verifies →
    ///      server calls registerAgent() with the proof hash.
    /// @param agent The agent's wallet address
    /// @param x402ProofHash Hash of the x402 payment proof used for registration
    /// @param platform Which AI platform the agent runs on (OpenClaw, Moltbook, etc.)
    function registerAgent(
        address agent,
        bytes32 x402ProofHash,
        FixerRegistryStorage.AgentPlatform platform
    ) external;

    /// @notice Deregister an AI agent
    /// @param agent The agent's wallet address to remove
    function deregisterAgent(address agent) external;

    /// @notice Update an agent's profile (bonus multiplier, verification status)
    /// @param agent The agent's wallet address
    /// @param bonusMultiplierBps Agent-specific bonus (0 = no bonus, max 5000 = 50%)
    /// @param verified Whether the agent is x402-verified
    function updateAgentProfile(
        address agent,
        uint16 bonusMultiplierBps,
        bool verified
    ) external;

    /// @notice Update an agent's x402 payment volume (trust signal from off-chain)
    /// @param agent The agent's wallet address
    /// @param additionalVolume Additional x402 volume to add
    function updateAgentX402Volume(address agent, uint128 additionalVolume) external;

    // ========================================================================
    // REFERRAL DELEGATION (Enhancement 4 — Marketplace)
    // ========================================================================

    /// @notice Delegate referral rights to another address
    /// @dev Allows delegate to use delegator's tier for referrals.
    ///      Off-chain x402 marketplace handles the payment side.
    /// @param delegate The address receiving delegation rights
    function delegateReferral(address delegate) external;

    /// @notice Revoke a referral delegation
    /// @param delegate The address losing delegation rights
    function revokeDelegation(address delegate) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Check if an address is a registered agent
    /// @param agent The address to check
    /// @return Whether the agent is registered
    function isRegisteredAgent(address agent) external view returns (bool);

    /// @notice Check if an agent is x402-verified
    /// @param agent The address to check
    /// @return Whether the agent is verified via x402
    function isVerifiedAgent(address agent) external view returns (bool);

    /// @notice Get the agent-specific bonus multiplier
    /// @param agent The agent's address
    /// @return bonusBps The bonus multiplier in basis points (0 if not an agent)
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
}
