// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFixerRegistry} from "./IFixerRegistry.sol";

/// @title IFixerCredential Interface
/// @notice Interface for the Fixer Credential NFT contract
/// @dev ERC-721 with ERC-5192 (Soulbound) extension
interface IFixerCredential {
    
    // ========================================================================
    // TYPES
    // ========================================================================
    
    /// @notice Credential data stored for each NFT
    struct Credential {
        IFixerRegistry.ReferrerTier tier;  // Current tier at time of last update
        uint128 totalVolume;               // Total volume at time of last update
        uint64 referralCount;              // Referral count at time of last update
        uint64 issuedAt;                   // Timestamp when credential was minted
        uint64 lastUpdated;                // Timestamp of last refresh
        bool locked;                       // Whether the token is soulbound
    }
    
    // ========================================================================
    // EVENTS
    // ========================================================================
    
    /// @notice Emitted when a credential is minted
    event CredentialMinted(
        address indexed referrer,
        uint256 indexed tokenId,
        IFixerRegistry.ReferrerTier tier
    );
    
    /// @notice Emitted when a credential is refreshed with latest stats
    event CredentialRefreshed(
        uint256 indexed tokenId,
        IFixerRegistry.ReferrerTier tier
    );
    
    /// @notice ERC-5192: Emitted when a token is locked (made soulbound)
    event Locked(uint256 indexed tokenId);
    
    /// @notice ERC-5192: Emitted when a token is unlocked
    event Unlocked(uint256 indexed tokenId);
    
    /// @notice ERC-4906: Emitted when metadata is updated
    event MetadataUpdate(uint256 indexed tokenId);
    
    // ========================================================================
    // ERRORS
    // ========================================================================
    
    /// @notice Thrown when attempting to mint a second credential
    error AlreadyMinted();
    
    /// @notice Thrown when attempting to mint without any referrals
    error NoReferralsYet();
    
    /// @notice Thrown when attempting to transfer a locked token
    error TokenLocked();
    
    /// @notice Thrown when querying a non-existent token
    error TokenNotFound();
    
    // ========================================================================
    // CORE FUNCTIONS
    // ========================================================================
    
    /// @notice Mints a soulbound credential NFT for a referrer
    /// @dev One credential per address, requires at least one referral
    /// @param referrer The referrer address to mint for
    /// @return tokenId The ID of the minted token
    function mint(address referrer) external returns (uint256 tokenId);
    
    /// @notice Refreshes a credential with the latest stats from the registry
    /// @dev Emits MetadataUpdate event for marketplace/frontend refresh
    /// @param tokenId The token ID to refresh
    function refresh(uint256 tokenId) external;
    
    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================
    
    /// @notice Gets the credential data for a token
    /// @param tokenId The token ID
    /// @return credential The credential data
    function getCredential(uint256 tokenId) external view returns (Credential memory credential);
    
    /// @notice Gets the token ID for a referrer
    /// @param referrer The referrer address
    /// @return tokenId The token ID (0 if not minted)
    function getTokenIdByReferrer(address referrer) external view returns (uint256 tokenId);
    
    /// @notice ERC-5192: Check if a token is locked (soulbound)
    /// @param tokenId The token ID to check
    /// @return Whether the token is locked
    function locked(uint256 tokenId) external view returns (bool);
    
    /// @notice Gets the registry address
    /// @return The registry contract address
    function registry() external view returns (IFixerRegistry);
}
