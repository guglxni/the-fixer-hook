// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title IERC8004IdentityRegistry
/// @notice Minimal read interface for ERC-8004 "Trustless Agents" Identity Registry
/// @dev The Identity Registry mints ERC-721 NFT agent identities with cryptographically
///      verified wallet associations. Used by FixerRegistryUpgradeable to verify agent
///      ownership during permissionless registration.
///
///      ERC-8004 Reference: https://eips.ethereum.org/EIPS/eip-8004
///      Authors: MetaMask, Ethereum Foundation, Google, Coinbase
///      Status: Draft (created August 13, 2025)
///
///      Global Agent ID Format: eip155:{chainId}:{identityRegistry}/{tokenId}
interface IERC8004IdentityRegistry {
    /// @notice Returns the owner of the agent NFT (ERC-721 standard)
    /// @param tokenId The agent's NFT token ID (agentId)
    /// @return owner The address that owns this agent identity NFT
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @notice Returns the cryptographically verified wallet for an agent
    /// @dev Wallet is set by the NFT owner via EIP-712 signed message.
    ///      Transferring the NFT clears this field, requiring re-verification.
    /// @param agentId The agent's NFT token ID
    /// @return wallet The agent's verified operational wallet address
    function getAgentWallet(uint256 agentId) external view returns (address wallet);

    /// @notice Returns metadata for an agent by key
    /// @dev Reserved keys include "agentWallet", endpoint types ("a2a", "mcp", "ens", "did")
    /// @param agentId The agent's NFT token ID
    /// @param key The metadata key
    /// @return value The metadata value as bytes
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory value);
}
