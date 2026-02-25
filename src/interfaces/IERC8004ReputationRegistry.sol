// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title IERC8004ReputationRegistry
/// @notice Read + Write interface for ERC-8004 "Trustless Agents" Reputation Registry
/// @dev Fixer Protocol both reads reputation to compute agent bonuses and writes
///      referral performance feedback, making it a first-class ERC-8004 ecosystem participant.
///
///      ERC-8004 Reference: https://eips.ethereum.org/EIPS/eip-8004
///
///      Feedback values are signed fixed-point (int128) with 0-18 decimals.
///      Tags enable multi-dimensional reputation (e.g., "fixer.referral", "fixer.volume").
interface IERC8004ReputationRegistry {
    // ========================================================================
    // READ: Query reputation for bonus calculation
    // ========================================================================

    /// @notice Get aggregated reputation summary for an agent
    /// @param agentId The agent's ERC-8004 NFT token ID
    /// @param clientAddresses Array of client addresses to filter by (empty = all)
    /// @param tag1 Primary tag filter (bytes32(0) = all tags)
    /// @param tag2 Secondary tag filter (bytes32(0) = all tags)
    /// @return count Number of feedback entries matching the filters
    /// @return summaryValue Aggregated reputation score (signed fixed-point)
    /// @return decimals Number of decimals for summaryValue interpretation
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        bytes32 tag1,
        bytes32 tag2
    ) external view returns (uint256 count, int128 summaryValue, uint8 decimals);

    /// @notice Read individual feedback entry
    /// @param agentId The agent's ERC-8004 NFT token ID
    /// @param clientAddress The client who gave feedback
    /// @param feedbackIndex Index of the feedback entry
    /// @return value The feedback score (signed fixed-point)
    /// @return decimals Decimals for value interpretation
    /// @return tag1 Primary tag
    /// @return tag2 Secondary tag
    /// @return isRevoked Whether this feedback was revoked
    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint256 feedbackIndex
    ) external view returns (int128 value, uint8 decimals, bytes32 tag1, bytes32 tag2, bool isRevoked);

    // ========================================================================
    // WRITE: Submit referral performance feedback
    // ========================================================================

    /// @notice Submit feedback for an agent's performance
    /// @dev Fixer Protocol calls this after processing referrals to build
    ///      on-chain reputation for agents in the ERC-8004 ecosystem.
    /// @param agentId The agent's ERC-8004 NFT token ID
    /// @param value The feedback score (signed fixed-point, e.g., 85 = positive)
    /// @param valueDecimals Number of decimals in value (0-18)
    /// @param tag1 Primary categorization tag (e.g., keccak256("fixer.referral"))
    /// @param tag2 Secondary categorization tag (e.g., keccak256("fixer.volume"))
    /// @param endpoint The interaction endpoint identifier
    /// @param feedbackURI URI to off-chain feedback details (can be empty)
    /// @param feedbackHash Hash of the off-chain feedback data (bytes32(0) if none)
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        bytes32 tag1,
        bytes32 tag2,
        bytes32 endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
}
