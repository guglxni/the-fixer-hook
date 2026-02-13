// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixerRegistry} from "../src/FixerRegistry.sol";
import {FixerCredential} from "../src/FixerCredential.sol";
import {IFixerRegistry} from "../src/interfaces/IFixerRegistry.sol";
import {IFixerCredential} from "../src/interfaces/IFixerCredential.sol";

/// @title FixerCredential v2.1 Unit Tests
/// @notice Comprehensive test suite for the soulbound NFT credential system
/// @dev Tests minting, soulbound enforcement, SVG generation, and registry integration
contract FixerCredentialTest is Test {
    
    FixerRegistry public registry;
    FixerCredential public credential;
    
    address public owner = makeAddr("owner");
    address public hook = makeAddr("hook");
    address public referrer = makeAddr("referrer");
    address public referrer2 = makeAddr("referrer2");
    address public swapper = makeAddr("swapper");
    address public minter = makeAddr("minter");
    
    bytes32 public poolId = keccak256("pool");
    
    function setUp() public {
        // Deploy registry
        registry = new FixerRegistry(owner);
        
        // Register hook
        vm.prank(owner);
        registry.registerHook(hook, poolId);
        
        // Deploy credential NFT
        credential = new FixerCredential(registry, owner);
    }
    
    /// @notice Helper to create referral activity for a referrer
    function _createReferralActivity(address _referrer, uint256 count, uint128 volumePerSwap) internal {
        for (uint256 i = 0; i < count; i++) {
            address uniqueSwapper = address(uint160(i + 1000));
            vm.prank(hook);
            registry.recordReferral(_referrer, uniqueSwapper, volumePerSwap, poolId);
        }
    }
    
    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================
    
    function test_Initialization() public view {
        assertEq(credential.name(), "Fixer Credential");
        assertEq(credential.symbol(), "FIXCRED");
        assertEq(address(credential.registry()), address(registry));
        assertEq(credential.owner(), owner);
    }
    
    function test_SupportsInterface() public view {
        // ERC-721
        assertTrue(credential.supportsInterface(0x80ac58cd));
        // ERC-721 Metadata
        assertTrue(credential.supportsInterface(0x5b5e139f));
        // ERC-165
        assertTrue(credential.supportsInterface(0x01ffc9a7));
        // ERC-5192 (Soulbound)
        assertTrue(credential.supportsInterface(0xb45a3c0e));
        // ERC-4906 (Metadata Update)
        assertTrue(credential.supportsInterface(0x49064906));
    }
    
    // ========================================================================
    // MINTING TESTS
    // ========================================================================
    
    function test_Mint_Success() public {
        // Create referral activity
        _createReferralActivity(referrer, 5, 1000e18);
        
        // Mint credential
        uint256 tokenId = credential.mint(referrer);
        
        assertEq(tokenId, 1);
        assertEq(credential.ownerOf(tokenId), referrer);
        assertEq(credential.getTokenIdByReferrer(referrer), tokenId);
        
        // Check credential data
        IFixerCredential.Credential memory cred = credential.getCredential(tokenId);
        assertEq(uint8(cred.tier), uint8(IFixerRegistry.ReferrerTier.Bronze));
        assertEq(cred.totalVolume, 5000e18);
        assertEq(cred.referralCount, 5);
        assertTrue(cred.locked);
        assertEq(cred.issuedAt, block.timestamp);
    }
    
    function test_Mint_WithDifferentTiers() public {
        // Create Silver-level activity (10 referrals, 10k volume)
        _createReferralActivity(referrer, 10, 1000e18);
        
        uint256 tokenId = credential.mint(referrer);
        
        IFixerCredential.Credential memory cred = credential.getCredential(tokenId);
        assertEq(uint8(cred.tier), uint8(IFixerRegistry.ReferrerTier.Silver));
    }
    
    function test_Mint_RevertIfAlreadyMinted() public {
        _createReferralActivity(referrer, 5, 1000e18);
        
        credential.mint(referrer);
        
        vm.expectRevert(IFixerCredential.AlreadyMinted.selector);
        credential.mint(referrer);
    }
    
    function test_Mint_RevertIfNoReferrals() public {
        vm.expectRevert(IFixerCredential.NoReferralsYet.selector);
        credential.mint(referrer);
    }
    
    function test_Mint_MultipleReferrers() public {
        _createReferralActivity(referrer, 5, 1000e18);
        _createReferralActivity(referrer2, 3, 2000e18);
        
        uint256 tokenId1 = credential.mint(referrer);
        uint256 tokenId2 = credential.mint(referrer2);
        
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(credential.ownerOf(tokenId1), referrer);
        assertEq(credential.ownerOf(tokenId2), referrer2);
    }
    
    function test_Mint_EmitsCorrectEvents() public {
        _createReferralActivity(referrer, 5, 1000e18);
        
        vm.expectEmit(true, true, false, true);
        emit IFixerCredential.CredentialMinted(referrer, 1, IFixerRegistry.ReferrerTier.Bronze);
        
        vm.expectEmit(true, false, false, false);
        emit IFixerCredential.Locked(1);
        
        credential.mint(referrer);
    }
    
    // ========================================================================
    // SOULBOUND ENFORCEMENT TESTS
    // ========================================================================
    
    function test_Soulbound_TransferBlocked() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        vm.expectRevert(IFixerCredential.TokenLocked.selector);
        vm.prank(referrer);
        credential.transferFrom(referrer, referrer2, tokenId);
    }
    
    function test_Soulbound_SafeTransferBlocked() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        vm.expectRevert(IFixerCredential.TokenLocked.selector);
        vm.prank(referrer);
        credential.safeTransferFrom(referrer, referrer2, tokenId);
    }
    
    function test_Soulbound_SafeTransferWithDataBlocked() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        vm.expectRevert(IFixerCredential.TokenLocked.selector);
        vm.prank(referrer);
        credential.safeTransferFrom(referrer, referrer2, tokenId, "");
    }
    
    function test_Locked_ReturnsTrue() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        assertTrue(credential.locked(tokenId));
    }
    
    function test_Unlock_AllowsTransfer() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        // Owner unlocks
        vm.prank(owner);
        credential.unlock(tokenId);
        
        assertFalse(credential.locked(tokenId));
        
        // Transfer now allowed
        vm.prank(referrer);
        credential.transferFrom(referrer, referrer2, tokenId);
        
        assertEq(credential.ownerOf(tokenId), referrer2);
    }
    
    function test_Lock_AfterUnlock() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        vm.startPrank(owner);
        credential.unlock(tokenId);
        credential.lock(tokenId);
        vm.stopPrank();
        
        assertTrue(credential.locked(tokenId));
        
        vm.expectRevert(IFixerCredential.TokenLocked.selector);
        vm.prank(referrer);
        credential.transferFrom(referrer, referrer2, tokenId);
    }
    
    function test_UnlockLock_OnlyOwner() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        vm.expectRevert();
        vm.prank(referrer);
        credential.unlock(tokenId);
        
        vm.prank(owner);
        credential.unlock(tokenId);
        
        vm.expectRevert();
        vm.prank(referrer);
        credential.lock(tokenId);
    }
    
    // ========================================================================
    // REFRESH TESTS
    // ========================================================================
    
    function test_Refresh_UpdatesStats() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        // Add more activity
        _createReferralActivity(referrer, 5, 1000e18);
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        // Refresh
        credential.refresh(tokenId);
        
        IFixerCredential.Credential memory cred = credential.getCredential(tokenId);
        assertEq(cred.totalVolume, 10000e18); // Updated
        assertEq(cred.referralCount, 10);     // Updated
        assertEq(cred.lastUpdated, block.timestamp);
    }
    
    function test_Refresh_TierUpgrade() public {
        // Start with Bronze
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        IFixerCredential.Credential memory cred = credential.getCredential(tokenId);
        assertEq(uint8(cred.tier), uint8(IFixerRegistry.ReferrerTier.Bronze));
        
        // Add activity to reach Silver (10 referrals, 10k volume)
        _createReferralActivity(referrer, 5, 1000e18);
        
        // Refresh to update tier
        credential.refresh(tokenId);
        
        cred = credential.getCredential(tokenId);
        assertEq(uint8(cred.tier), uint8(IFixerRegistry.ReferrerTier.Silver));
    }
    
    function test_Refresh_EmitsEvents() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        _createReferralActivity(referrer, 5, 1000e18);
        
        vm.expectEmit(true, false, false, true);
        emit IFixerCredential.CredentialRefreshed(tokenId, IFixerRegistry.ReferrerTier.Silver);
        
        vm.expectEmit(true, false, false, false);
        emit IFixerCredential.MetadataUpdate(tokenId);
        
        credential.refresh(tokenId);
    }
    
    function test_Refresh_RevertIfTokenNotFound() public {
        vm.expectRevert(IFixerCredential.TokenNotFound.selector);
        credential.refresh(999);
    }
    
    // ========================================================================
    // METADATA TESTS
    // ========================================================================
    
    function test_TokenURI_ReturnsValidDataURI() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        string memory uri = credential.tokenURI(tokenId);
        
        // Check it starts with data URI prefix
        assertTrue(bytes(uri).length > 29); // At least "data:application/json;base64,"
        
        // Check prefix
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(bytes(uri)[i], prefix[i]);
        }
    }
    
    function test_TokenURI_RevertIfTokenNotFound() public {
        vm.expectRevert(IFixerCredential.TokenNotFound.selector);
        credential.tokenURI(999);
    }
    
    function test_TokenURI_DifferentTiers() public {
        // Bronze (default)
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 bronzeToken = credential.mint(referrer);
        
        // Silver (10 referrals, 10k volume)
        _createReferralActivity(referrer2, 10, 1000e18);
        uint256 silverToken = credential.mint(referrer2);
        
        string memory bronzeUri = credential.tokenURI(bronzeToken);
        string memory silverUri = credential.tokenURI(silverToken);
        
        // URIs should be different (different tiers)
        assertTrue(keccak256(bytes(bronzeUri)) != keccak256(bytes(silverUri)));
    }
    
    // ========================================================================
    // VIEW FUNCTION TESTS
    // ========================================================================
    
    function test_GetCredential() public {
        _createReferralActivity(referrer, 10, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        IFixerCredential.Credential memory cred = credential.getCredential(tokenId);
        
        assertEq(uint8(cred.tier), uint8(IFixerRegistry.ReferrerTier.Silver));
        assertEq(cred.totalVolume, 10000e18);
        assertEq(cred.referralCount, 10);
        assertEq(cred.issuedAt, block.timestamp);
        assertEq(cred.lastUpdated, block.timestamp);
        assertTrue(cred.locked);
    }
    
    function test_GetTokenIdByReferrer() public {
        _createReferralActivity(referrer, 5, 1000e18);
        uint256 tokenId = credential.mint(referrer);
        
        assertEq(credential.getTokenIdByReferrer(referrer), tokenId);
        assertEq(credential.getTokenIdByReferrer(referrer2), 0); // No credential
    }
    
    function test_Locked_RevertIfTokenNotFound() public {
        vm.expectRevert(IFixerCredential.TokenNotFound.selector);
        credential.locked(999);
    }
}

/// @title FixerCredential Fuzz Tests
contract FixerCredentialFuzzTest is Test {
    
    FixerRegistry public registry;
    FixerCredential public credential;
    
    address public owner = makeAddr("owner");
    address public hook = makeAddr("hook");
    bytes32 public poolId = keccak256("pool");
    
    function setUp() public {
        registry = new FixerRegistry(owner);
        vm.prank(owner);
        registry.registerHook(hook, poolId);
        credential = new FixerCredential(registry, owner);
    }
    
    function testFuzz_MintWithAnyReferrer(address referrer) public {
        vm.assume(referrer != address(0));
        vm.assume(referrer.code.length == 0); // EOA only for SafeMint
        
        // Create activity
        address swapper = makeAddr("swapper");
        vm.assume(swapper != referrer);
        
        vm.prank(hook);
        registry.recordReferral(referrer, swapper, 1000e18, poolId);
        
        uint256 tokenId = credential.mint(referrer);
        
        assertEq(credential.ownerOf(tokenId), referrer);
        assertTrue(credential.locked(tokenId));
    }
    
    function testFuzz_MintSequentialIds(uint8 count) public {
        count = uint8(bound(count, 1, 50));
        
        for (uint8 i = 0; i < count; i++) {
            address referrer = address(uint160(i + 1000));
            address swapper = address(uint160(i + 2000));
            
            vm.prank(hook);
            registry.recordReferral(referrer, swapper, 1000e18, poolId);
            
            uint256 tokenId = credential.mint(referrer);
            assertEq(tokenId, i + 1);
        }
    }
}

/// @title FixerCredential Gas Tests
contract FixerCredentialGasTest is Test {
    
    FixerRegistry public registry;
    FixerCredential public credential;
    
    address public owner = makeAddr("owner");
    address public hook = makeAddr("hook");
    address public referrer = makeAddr("referrer");
    bytes32 public poolId = keccak256("pool");
    
    function setUp() public {
        registry = new FixerRegistry(owner);
        vm.prank(owner);
        registry.registerHook(hook, poolId);
        credential = new FixerCredential(registry, owner);
        
        // Create referral activity
        for (uint256 i = 0; i < 10; i++) {
            address swapper = address(uint160(i + 1000));
            vm.prank(hook);
            registry.recordReferral(referrer, swapper, 1000e18, poolId);
        }
    }
    
    function test_GasMint() public {
        uint256 gasBefore = gasleft();
        credential.mint(referrer);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for mint", gasUsed);
        assertLt(gasUsed, 200_000, "Mint should use reasonable gas");
    }
    
    function test_GasRefresh() public {
        uint256 tokenId = credential.mint(referrer);
        
        uint256 gasBefore = gasleft();
        credential.refresh(tokenId);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for refresh", gasUsed);
        assertLt(gasUsed, 50_000, "Refresh should be cheaper than mint");
    }
    
    function test_GasTokenURI() public {
        uint256 tokenId = credential.mint(referrer);
        
        uint256 gasBefore = gasleft();
        credential.tokenURI(tokenId);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas for tokenURI", gasUsed);
        // On-chain SVG generation with Base64 encoding is inherently gas-intensive
        assertLt(gasUsed, 350_000, "TokenURI should be reasonable for on-chain SVG generation");
    }
}
