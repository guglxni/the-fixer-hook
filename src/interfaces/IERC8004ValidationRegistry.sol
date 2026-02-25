// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title IERC8004ValidationRegistry
/// @notice Read interface for ERC-8004 "Trustless Agents" Validation Registry
/// @dev Used to check third-party validation scores for agent tier gating.
///      Validators provide scored responses (0 = failed, 100 = passed) via
///      independent verification methods (re-execution, zkML, TEE attestation).
///
///      ERC-8004 Reference: https://eips.ethereum.org/EIPS/eip-8004
interface IERC8004ValidationRegistry {
    /// @notice Get aggregated validation summary for an agent
    /// @param agentId The agent's ERC-8004 NFT token ID
    /// @param validatorAddresses Array of validator addresses to filter (empty = all)
    /// @param tag Validation tag filter (bytes32(0) = all tags)
    /// @return count Number of validations matching the filters
    /// @return averageResponse Average validation score (0-100)
    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        bytes32 tag
    ) external view returns (uint256 count, uint8 averageResponse);
}
