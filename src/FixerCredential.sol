// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// Token Standard (Solmate for gas efficiency)
import {ERC721} from "solmate/src/tokens/ERC721.sol";

// Solady for gas-optimized utilities
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// Interfaces
import {IFixerRegistry} from "./interfaces/IFixerRegistry.sol";
import {IFixerCredential} from "./interfaces/IFixerCredential.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerCredential
/// @author Aaryan Guglani
/// @notice Soulbound NFT credentials for Fixer referrers
/// @dev ERC-721 with ERC-5192 (Minimal Soulbound) extension
///
/// Architecture:
/// - Soulbound by default (non-transferable)
/// - Fetches stats from FixerRegistry
/// - On-chain SVG generation
/// - Dynamic metadata updates
///
/// v2.1 Features:
/// - ERC-5192 compliant soulbound tokens
/// - On-chain SVG generation with tier-based colors
/// - Refresh functionality to update stats
/// - One credential per referrer address
/// - ERC-4906 metadata update events
contract FixerCredential is IFixerCredential, ERC721, Ownable {
    using LibString for uint256;
    using LibString for address;
    
    // ========================================================================
    // CONSTANTS
    // ========================================================================
    
    /// @notice ERC-5192 interface ID
    bytes4 private constant IERC5192_ID = 0xb45a3c0e;
    
    /// @notice ERC-4906 interface ID
    bytes4 private constant IERC4906_ID = 0x49064906;
    
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================
    
    /// @notice The Fixer Registry contract
    IFixerRegistry public immutable override registry;
    
    /// @notice Token ID counter
    uint256 private _nextTokenId = 1;
    
    /// @notice Mapping from token ID to credential data
    mapping(uint256 => Credential) internal _credentials;
    
    /// @notice Mapping from referrer address to token ID
    mapping(address => uint256) internal _referrerToTokenId;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /// @notice Initializes the credential NFT contract
    /// @param _registry The FixerRegistry contract address
    /// @param _owner The contract owner address
    constructor(
        IFixerRegistry _registry,
        address _owner
    ) ERC721("Fixer Credential", "FIXCRED") {
        registry = _registry;
        _initializeOwner(_owner);
    }
    
    // ========================================================================
    // ERC-165 SUPPORT
    // ========================================================================
    
    /// @notice Checks if the contract supports an interface
    /// @param interfaceId The interface identifier
    /// @return Whether the interface is supported
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return 
            interfaceId == IERC5192_ID ||     // ERC-5192 Soulbound
            interfaceId == IERC4906_ID ||     // ERC-4906 Metadata Update
            interfaceId == 0x80ac58cd ||      // ERC-721
            interfaceId == 0x5b5e139f ||      // ERC-721 Metadata
            interfaceId == 0x01ffc9a7;        // ERC-165
    }
    
    // ========================================================================
    // CORE FUNCTIONS
    // ========================================================================
    
    /// @inheritdoc IFixerCredential
    function mint(address referrer) external returns (uint256 tokenId) {
        // Check if already minted
        if (_referrerToTokenId[referrer] != 0) revert AlreadyMinted();
        
        // Fetch stats from registry
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(referrer);
        
        // Require at least one referral
        if (stats.referralCount == 0) revert NoReferralsYet();
        
        // Assign token ID
        tokenId = _nextTokenId++;

        // FIX: F-06 — Set all state BEFORE _safeMint to prevent reentrancy
        // via onERC721Received callback bypassing the AlreadyMinted check.
        _credentials[tokenId] = Credential({
            tier: stats.tier,
            totalVolume: stats.totalVolume,
            referralCount: stats.referralCount,
            issuedAt: uint64(block.timestamp),
            lastUpdated: uint64(block.timestamp),
            locked: true  // Soulbound by default
        });
        _referrerToTokenId[referrer] = tokenId;
        
        // Mint token (may call onERC721Received — state is already set)
        _safeMint(referrer, tokenId);
        
        emit CredentialMinted(referrer, tokenId, stats.tier);
        emit Locked(tokenId);
        
        return tokenId;
    }
    
    /// @inheritdoc IFixerCredential
    function refresh(uint256 tokenId) external {
        // Check token exists
        address owner = _ownerOf[tokenId];
        if (owner == address(0)) revert TokenNotFound();
        
        // Fetch latest stats from registry
        IFixerRegistry.ReferrerStats memory stats = registry.getReferrerStats(owner);
        
        // Update credential data
        Credential storage cred = _credentials[tokenId];
        cred.tier = stats.tier;
        cred.totalVolume = stats.totalVolume;
        cred.referralCount = stats.referralCount;
        cred.lastUpdated = uint64(block.timestamp);
        
        emit CredentialRefreshed(tokenId, stats.tier);
        emit MetadataUpdate(tokenId);
    }
    
    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================
    
    /// @inheritdoc IFixerCredential
    function getCredential(uint256 tokenId) external view returns (Credential memory) {
        if (_ownerOf[tokenId] == address(0)) revert TokenNotFound();
        return _credentials[tokenId];
    }
    
    /// @inheritdoc IFixerCredential
    function getTokenIdByReferrer(address referrer) external view returns (uint256) {
        return _referrerToTokenId[referrer];
    }
    
    /// @inheritdoc IFixerCredential
    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf[tokenId] == address(0)) revert TokenNotFound();
        return _credentials[tokenId].locked;
    }
    
    // ========================================================================
    // METADATA GENERATION
    // ========================================================================
    
    /// @notice Generates the token URI with on-chain SVG
    /// @param tokenId The token ID
    /// @return The data URI with JSON metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf[tokenId] == address(0)) revert TokenNotFound();
        
        Credential memory cred = _credentials[tokenId];
        string memory tierName = _getTierName(cred.tier);
        string memory tierColor = _getTierColor(cred.tier);
        
        // Generate SVG
        string memory svg = _generateSVG(tokenId, cred, tierName, tierColor);
        
        // Generate JSON metadata
        string memory json = string.concat(
            '{"name":"Fixer Credential #', tokenId.toString(), '",',
            '"description":"On-chain referral reputation credential for the Fixer Protocol",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            '"attributes":[',
                '{"trait_type":"Tier","value":"', tierName, '"},',
                '{"trait_type":"Total Volume","value":', _formatVolume(cred.totalVolume), '},',
                '{"trait_type":"Referral Count","value":', uint256(cred.referralCount).toString(), '},',
                '{"trait_type":"Soulbound","value":"', cred.locked ? 'Yes' : 'No', '"},',
                '{"trait_type":"Issued At","display_type":"date","value":', uint256(cred.issuedAt).toString(), '},',
                '{"trait_type":"Last Updated","display_type":"date","value":', uint256(cred.lastUpdated).toString(), '}',
            ']}'
        );
        
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        );
    }
    
    /// @notice Generates the on-chain SVG for a credential
    /// @param tokenId The token ID
    /// @param cred The credential data
    /// @param tierName The tier name string
    /// @param tierColor The tier color hex code
    /// @return The SVG string
    function _generateSVG(
        uint256 tokenId,
        Credential memory cred,
        string memory tierName,
        string memory tierColor
    ) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 500">',
            _generateDefs(tierColor),
            _generateBackground(),
            _generateBadge(tierColor),
            _generateText(tokenId, cred, tierName, tierColor),
            _generateFooter(cred),
            '</svg>'
        );
    }
    
    /// @notice Generates SVG defs (gradients, filters)
    function _generateDefs(string memory tierColor) internal pure returns (string memory) {
        return string.concat(
            '<defs>',
            '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:#0a0a1a"/>',
            '<stop offset="50%" style="stop-color:#1a1a3e"/>',
            '<stop offset="100%" style="stop-color:#0a0a1a"/>',
            '</linearGradient>',
            '<linearGradient id="tierGrad" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:', tierColor, ';stop-opacity:1"/>',
            '<stop offset="100%" style="stop-color:', tierColor, ';stop-opacity:0.6"/>',
            '</linearGradient>',
            '<filter id="glow">',
            '<feGaussianBlur stdDeviation="3" result="coloredBlur"/>',
            '<feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge>',
            '</filter>',
            '</defs>'
        );
    }
    
    /// @notice Generates SVG background
    function _generateBackground() internal pure returns (string memory) {
        return string.concat(
            '<rect width="400" height="500" fill="url(#bg)"/>',
            '<rect x="10" y="10" width="380" height="480" rx="20" fill="none" stroke="#333" stroke-width="2"/>'
        );
    }
    
    /// @notice Generates the tier badge
    function _generateBadge(string memory tierColor) internal pure returns (string memory) {
        return string.concat(
            '<circle cx="200" cy="130" r="70" fill="url(#tierGrad)" filter="url(#glow)" opacity="0.9"/>',
            '<circle cx="200" cy="130" r="60" fill="none" stroke="', tierColor, '" stroke-width="2" opacity="0.5"/>',
            '<text x="200" y="145" text-anchor="middle" fill="white" font-size="28" font-weight="bold" font-family="Arial">FIX</text>'
        );
    }
    
    /// @notice Generates the text content
    function _generateText(
        uint256 tokenId,
        Credential memory cred,
        string memory tierName,
        string memory tierColor
    ) internal pure returns (string memory) {
        return string.concat(
            '<text x="200" y="250" text-anchor="middle" fill="', tierColor, '" font-size="32" font-weight="bold" font-family="Arial">', tierName, '</text>',
            '<text x="200" y="290" text-anchor="middle" fill="#888" font-size="14" font-family="Arial">FIXER CREDENTIAL</text>',
            '<line x1="60" y1="320" x2="340" y2="320" stroke="#333" stroke-width="1"/>',
            '<text x="60" y="360" fill="#666" font-size="14" font-family="Arial">Referrals</text>',
            '<text x="340" y="360" text-anchor="end" fill="#fff" font-size="16" font-weight="bold" font-family="Arial">', uint256(cred.referralCount).toString(), '</text>',
            '<text x="60" y="395" fill="#666" font-size="14" font-family="Arial">Volume</text>',
            '<text x="340" y="395" text-anchor="end" fill="#fff" font-size="16" font-weight="bold" font-family="Arial">', _formatVolumeShort(cred.totalVolume), '</text>',
            '<text x="200" y="470" text-anchor="middle" fill="#444" font-size="12" font-family="Arial">#', tokenId.toString(), '</text>'
        );
    }
    
    /// @notice Generates the footer with soulbound indicator
    function _generateFooter(Credential memory cred) internal pure returns (string memory) {
        if (cred.locked) {
            return '<text x="200" y="490" text-anchor="middle" fill="#666" font-size="10" font-family="Arial">SOULBOUND</text>';
        }
        return '';
    }
    
    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    /// @notice Gets the tier name string
    function _getTierName(IFixerRegistry.ReferrerTier tier) internal pure returns (string memory) {
        if (tier == IFixerRegistry.ReferrerTier.Platinum) return "PLATINUM";
        if (tier == IFixerRegistry.ReferrerTier.Gold) return "GOLD";
        if (tier == IFixerRegistry.ReferrerTier.Silver) return "SILVER";
        return "BRONZE";
    }
    
    /// @notice Gets the tier color hex code
    function _getTierColor(IFixerRegistry.ReferrerTier tier) internal pure returns (string memory) {
        if (tier == IFixerRegistry.ReferrerTier.Platinum) return "#E5E4E2";
        if (tier == IFixerRegistry.ReferrerTier.Gold) return "#FFD700";
        if (tier == IFixerRegistry.ReferrerTier.Silver) return "#C0C0C0";
        return "#CD7F32";
    }
    
    /// @notice Formats volume as a string with full precision
    function _formatVolume(uint128 volume) internal pure returns (string memory) {
        return uint256(volume).toString();
    }
    
    /// @notice Formats volume in a short human-readable format
    function _formatVolumeShort(uint128 volume) internal pure returns (string memory) {
        uint256 vol = uint256(volume) / 1e18;
        
        if (vol >= 1_000_000) {
            return string.concat((vol / 1_000_000).toString(), ".", ((vol % 1_000_000) / 100_000).toString(), "M");
        } else if (vol >= 1_000) {
            return string.concat((vol / 1_000).toString(), ".", ((vol % 1_000) / 100).toString(), "K");
        } else {
            return vol.toString();
        }
    }
    
    // ========================================================================
    // TRANSFER RESTRICTIONS (SOULBOUND)
    // ========================================================================

    /// @notice Override approve to enforce soulbound (ERC-5192 compliance)
    /// @dev FIX: F-17 — Approvals should revert for locked tokens per ERC-5192.
    ///      Previously approvals succeeded but transfers failed — confusing UX.
    function approve(address spender, uint256 id) public override {
        if (_credentials[id].locked) {
            revert TokenLocked();
        }
        super.approve(spender, id);
    }

    /// @notice Override setApprovalForAll to enforce soulbound
    /// @dev Reverts if caller owns any locked tokens. Since all credentials are
    ///      soulbound by default, this effectively blocks setApprovalForAll.
    function setApprovalForAll(address operator, bool approved) public override {
        // If approving (not revoking), check that the caller has a locked credential
        if (approved) {
            uint256 tokenId = _referrerToTokenId[msg.sender];
            if (tokenId != 0 && _credentials[tokenId].locked) {
                revert TokenLocked();
            }
        }
        super.setApprovalForAll(operator, approved);
    }

    /// @notice Override transfer to enforce soulbound
    function transferFrom(address from, address to, uint256 id) public override {
        // Allow minting (from = 0) but block transfers if locked
        if (from != address(0) && _credentials[id].locked) {
            revert TokenLocked();
        }
        super.transferFrom(from, to, id);
    }
    
    /// @notice Override safeTransferFrom to enforce soulbound
    function safeTransferFrom(address from, address to, uint256 id) public override {
        if (from != address(0) && _credentials[id].locked) {
            revert TokenLocked();
        }
        super.safeTransferFrom(from, to, id);
    }
    
    /// @notice Override safeTransferFrom with data to enforce soulbound
    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) public override {
        if (from != address(0) && _credentials[id].locked) {
            revert TokenLocked();
        }
        super.safeTransferFrom(from, to, id, data);
    }
    
    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================
    
    /// @notice Unlocks a token (removes soulbound restriction)
    /// @dev Only callable by owner, for future governance decisions
    /// @param tokenId The token ID to unlock
    function unlock(uint256 tokenId) external onlyOwner {
        if (_ownerOf[tokenId] == address(0)) revert TokenNotFound();
        
        _credentials[tokenId].locked = false;
        emit Unlocked(tokenId);
    }
    
    /// @notice Locks a token (restores soulbound restriction)
    /// @dev Only callable by owner
    /// @param tokenId The token ID to lock
    function lock(uint256 tokenId) external onlyOwner {
        if (_ownerOf[tokenId] == address(0)) revert TokenNotFound();
        
        _credentials[tokenId].locked = true;
        emit Locked(tokenId);
    }
}
