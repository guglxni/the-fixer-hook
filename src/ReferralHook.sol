// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// Uniswap v4 Core
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

// Uniswap v4 Periphery
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Token Standard (Solmate for gas efficiency)
import {ERC20} from "solmate/src/tokens/ERC20.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title ReferralHook
/// @author Aaryan Guglani
/// @notice On-chain affiliate rewards for Uniswap v4 pools
/// @dev Combines hook logic with ERC20 token minting for referral rewards
/// 
/// Architecture:
/// - Inherits BaseHook for Uniswap v4 hook functionality
/// - Inherits ERC20 to act as the reward token itself
/// - Only enables afterSwap permission for minimal gas overhead
///
/// Workflow:
/// 1. User initiates swap with encoded referrer address in hookData
/// 2. PoolManager executes swap, then calls afterSwap on this hook
/// 3. Hook decodes referrer, validates (not zero, not self-referral)
/// 4. If valid, mints REWARD_AMOUNT tokens to referrer
contract ReferralHook is BaseHook, ERC20 {
    
    // ========================================================================
    // CONSTANTS
    // ========================================================================
    
    /// @notice Fixed reward amount per successful referral (10 tokens)
    /// @dev Using 10e18 for standard 18 decimal token representation
    uint256 public constant REWARD_AMOUNT = 10 * 1e18;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /// @notice Initializes the ReferralHook with PoolManager and token details
    /// @param _manager Address of the Uniswap v4 PoolManager
    /// @dev Hook address must have correct permission bits set (afterSwap = bit 7)
    constructor(IPoolManager _manager) 
        BaseHook(_manager) 
        ERC20("Referral Token", "REF", 18) 
    {}
    
    // ========================================================================
    // HOOK CONFIGURATION
    // ========================================================================
    
    /// @notice Defines which hook lifecycle functions should be called
    /// @dev Only afterSwap is enabled to minimize gas overhead
    /// @return Permissions struct with all flags set appropriately
    function getHookPermissions() 
        public 
        pure 
        override 
        returns (Hooks.Permissions memory) 
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,                    // ENABLED: Issue rewards after swap
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    // ========================================================================
    // HOOK LOGIC
    // ========================================================================
    
    /// @notice Called by PoolManager after each swap to process referral rewards
    /// @dev This is the core logic that validates and rewards referrers
    /// 
    /// Validation steps:
    /// 1. Check if hookData contains referrer (length > 0)
    /// 2. Decode referrer address from hookData
    /// 3. Ensure referrer is not zero address
    /// 4. Ensure referrer is not the transaction originator (anti-gaming)
    /// 5. If all checks pass, mint REWARD_AMOUNT tokens to referrer
    ///
    /// @param sender The address that called swap (typically a router contract)
    /// @param key The pool's identifying key (unused in current implementation)
    /// @param params The swap parameters (unused in current implementation)
    /// @param delta The balance changes from the swap (unused in current implementation)
    /// @param hookData Encoded referrer address: abi.encode(address referrer)
    /// @return selector The afterSwap function selector for validation
    /// @return deltaUnspecified The delta modification (always 0, we don't modify amounts)
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        
        // ====================================================================
        // STEP 1: Check if referral data exists
        // ====================================================================
        // If hookData is empty, this is a normal swap without referral intent.
        // Skip all processing and return early to save gas.
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 2: Decode the referrer address
        // ====================================================================
        // hookData format: abi.encode(address referrer)
        // This produces a 32-byte padded address representation.
        // If hookData is malformed, abi.decode will revert.
        address referrer = abi.decode(hookData, (address));
        
        // ====================================================================
        // STEP 3: Validate - Check for zero address
        // ====================================================================
        // Minting to address(0) would burn tokens. Reject this case.
        if (referrer == address(0)) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 4: Validate - Prevent self-referral
        // ====================================================================
        // Anti-gaming measure: Users should not be able to refer themselves.
        // 
        // Why tx.origin instead of sender?
        // - `sender` is often a router contract (SwapRouter), not the user
        // - `tx.origin` gives us the actual EOA that initiated the transaction
        // - This is safe for anti-gaming (not for authentication)
        //
        // Limitation: Does not prevent cross-wallet referral (Sybil attack)
        // Future versions could add volume thresholds to mitigate.
        if (referrer == tx.origin) {
            return (this.afterSwap.selector, 0);
        }
        
        // ====================================================================
        // STEP 5: Mint reward tokens
        // ====================================================================
        // All validation passed. Mint REWARD_AMOUNT tokens to the referrer.
        // _mint is inherited from Solmate's ERC20 implementation.
        _mint(referrer, REWARD_AMOUNT);
        
        // ====================================================================
        // STEP 6: Return success
        // ====================================================================
        // - Selector: Required for hook validation by PoolManager
        // - int128(0): No delta modification (we don't take fees or modify amounts)
        return (this.afterSwap.selector, 0);
    }
}
