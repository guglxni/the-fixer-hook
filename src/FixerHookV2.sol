// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ============================================================================
// IMPORTS
// ============================================================================

// Uniswap v4 Core
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

// Uniswap v4 Periphery
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Registry Interface
import {IFixerRegistry} from "./interfaces/IFixerRegistry.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";

// Trusted Router Pattern (ERC-4337 compatible user identification)
import {IMsgSender} from "./interfaces/IMsgSender.sol";

// ============================================================================
// CONTRACT
// ============================================================================

/// @title FixerHookV2
/// @author Aaryan Guglani
/// @notice Lightweight Uniswap v4 hook that delegates to FixerRegistry
/// @dev For v2.0 cross-pool tracking - each pool has its own hook instance
///
/// Architecture:
/// - Minimal on-chain footprint (no token, no stats storage)
/// - Delegates all referral processing to the central FixerRegistry
/// - Each hook is registered with the registry for a specific pool
/// - Volume calculation is done here, reward calculation in registry
///
/// @custom:security-note Unsupported Token Types:
///   - Fee-on-transfer tokens: Volume from BalanceDelta may not match actual
///     transferred amounts. Referral rewards may be overstated.
///   - Rebasing tokens: Not accounted for in volume calculations.
///   - ERC-777 tokens: Callback hooks could interfere with gas estimates.
///   - Pausable/blocklist tokens: May cause unexpected swap reverts.
///   This hook is observation-only (returns (bytes4, int128(0))) and does not
///   take/settle tokens, so no funds are at risk.
///
/// Key Features:
/// - Immutable registry reference (gas efficient)
/// - Configurable quote token index per pool
/// - Graceful error handling (swap never fails due to hook)
/// - Gas optimized: minimal storage, no token operations
/// - Trusted Router pattern for ERC-4337 compatible user identification
contract FixerHookV2 is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    // ========================================================================
    // EVENTS
    // ========================================================================
    
    /// @notice Emitted when a referral is processed through this hook
    event ReferralProcessed(
        address indexed referrer,
        address indexed swapper,
        bytes32 indexed poolId,
        uint256 volume,
        uint256 reward
    );
    
    /// @notice Emitted when the hook fails gracefully
    event HookError(bytes32 indexed poolId, string reason);
    
    /// @notice Emitted when a trusted router is added or removed
    event TrustedRouterUpdated(address indexed router, bool trusted);
    
    /// @notice Emitted when swapper resolution falls back to tx.origin
    /// @dev Monitor this event — high frequency indicates routers need IMsgSender support
    event SwapperFallbackToTxOrigin(address indexed router, address txOrigin);
    
    // ========================================================================
    // ERRORS
    // ========================================================================
    
    /// @notice Thrown when the registry address is invalid
    error InvalidRegistry();
    
    /// @notice Thrown when quote token index is invalid
    error InvalidQuoteTokenIndex();
    
    /// @notice Thrown when a non-owner calls an owner-only function
    error NotOwner();
    
    // ========================================================================
    // IMMUTABLES
    // ========================================================================
    
    /// @notice The central Fixer Registry contract
    IFixerRegistry public immutable registry;
    
    /// @notice The pool ID this hook is associated with
    bytes32 public immutable poolId;
    
    /// @notice Quote token index for volume calculation (0 = token0, 1 = token1)
    uint256 public immutable quoteTokenIndex;
    
    /// @notice The deployer/admin who can manage trusted routers
    address public immutable owner;
    
    // ========================================================================
    // STORAGE
    // ========================================================================
    
    /// @notice Allowlist of trusted routers that implement IMsgSender
    /// @dev Used to resolve the actual end-user behind a swap.
    ///      When sender is a trusted router, we call msgSender() to get the
    ///      authenticated user (compatible with ERC-4337 Smart Accounts).
    ///      When sender is NOT trusted, we fall back to tx.origin.
    mapping(address => bool) public trustedRouters;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /// @notice Initializes the hook with registry and pool configuration
    /// @dev Constructs the PoolKey internally using address(this) to avoid the
    ///      circular dependency where the PoolKey.hooks field needs the hook's
    ///      own address (which is unknown before deployment when mining CREATE2 salts).
    /// @param _manager The Uniswap v4 PoolManager
    /// @param _registry The FixerRegistry contract address
    /// @param _currency0 The lower currency of the pool (sorted numerically)
    /// @param _currency1 The higher currency of the pool (sorted numerically)
    /// @param _fee The pool LP fee
    /// @param _tickSpacing The pool tick spacing
    /// @param _quoteTokenIndex Which token is the quote token (0 or 1)
    constructor(
        IPoolManager _manager,
        IFixerRegistry _registry,
        Currency _currency0,
        Currency _currency1,
        uint24 _fee,
        int24 _tickSpacing,
        uint256 _quoteTokenIndex
    ) BaseHook(_manager) {
        if (address(_registry) == address(0)) revert InvalidRegistry();
        if (_quoteTokenIndex > 1) revert InvalidQuoteTokenIndex();
        
        registry = _registry;
        // Construct the PoolKey using address(this) as the hooks field.
        // This produces the correct poolId that matches the actual Uniswap v4 pool.
        PoolKey memory key = PoolKey({
            currency0: _currency0,
            currency1: _currency1,
            fee: _fee,
            tickSpacing: _tickSpacing,
            hooks: IHooks(address(this))
        });
        poolId = key.toId().toBytes32();
        quoteTokenIndex = _quoteTokenIndex;
        owner = msg.sender;
    }
    
    // ========================================================================
    // ROUTER MANAGEMENT
    // ========================================================================
    
    /// @notice Add or remove a trusted router from the allowlist
    /// @dev Only the deployer/owner can manage the router allowlist.
    ///      Trusted routers must implement IMsgSender to resolve the actual user.
    /// @param router The router address to update
    /// @param trusted Whether the router should be trusted
    function setTrustedRouter(address router, bool trusted) external {
        if (msg.sender != owner) revert NotOwner();
        trustedRouters[router] = trusted;
        emit TrustedRouterUpdated(router, trusted);
    }
    
    // ========================================================================
    // HOOK CONFIGURATION
    // ========================================================================
    
    /// @notice Defines which hook lifecycle functions should be called
    /// @dev Only afterSwap is enabled to minimize gas overhead
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
            afterSwap: true,                    // ENABLED: Process referrals after swap
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
    /// @dev Delegates referral recording to the central registry
    ///
    /// Flow:
    /// 1. Check if hookData contains referrer
    /// 2. Decode and validate referrer
    /// 3. Calculate swap volume using quote token
    /// 4. Call registry.recordReferral()
    /// 5. Handle any errors gracefully
    ///
    /// @param sender The address that called swap (typically a router)
    /// @param key The pool's identifying key
    /// @param params The swap parameters (unused)
    /// @param delta The balance changes from the swap
    /// @param hookData Encoded referrer address
    /// @return selector The afterSwap function selector
    /// @return deltaUnspecified Always 0 (no delta modification)
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Step 1: Check if referral data exists
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0);
        }
        
        // Step 2: Decode referrer address
        address referrer = address(0);
        try this.decodeReferrer(hookData) returns (address decoded) {
            referrer = decoded;
        } catch {
            // Malformed data - skip silently
            return (this.afterSwap.selector, 0);
        }
        
        // Step 3: Resolve the actual swapper (Trusted Router Pattern)
        // Uses IMsgSender for ERC-4337 compatibility; falls back to tx.origin
        address swapper = _resolveSwapper(sender);
        
        // Step 4: Basic validation
        if (referrer == address(0) || referrer == swapper) {
            return (this.afterSwap.selector, 0);
        }
        
        // Step 5: Calculate swap volume using quote token
        uint256 volume = _calculateSwapVolume(delta);
        
        // Step 6: Delegate to registry (with graceful error handling)
        try registry.recordReferral(referrer, swapper, volume, poolId) returns (uint256 reward) {
            if (reward > 0) {
                emit ReferralProcessed(referrer, swapper, poolId, volume, reward);
            }
        } catch Error(string memory reason) {
            emit HookError(poolId, reason);
        } catch {
            emit HookError(poolId, "UnknownError");
        }
        
        return (this.afterSwap.selector, 0);
    }
    
    // ========================================================================
    // VOLUME CALCULATION
    // ========================================================================
    
    /// @notice Calculates the swap volume using the configured quote token
    /// @dev Uses quoteTokenIndex to determine which token amount to use
    /// @param delta The balance changes from the swap
    /// @return volume The calculated volume in quote token units
    function _calculateSwapVolume(BalanceDelta delta) internal view returns (uint256) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        
        // Select amount based on quote token configuration
        int128 quoteAmount = quoteTokenIndex == 0 ? amount0 : amount1;
        
        // Convert to absolute value
        return quoteAmount < 0 
            ? uint256(uint128(-quoteAmount)) 
            : uint256(uint128(quoteAmount));
    }
    
    // ========================================================================
    // SWAPPER RESOLUTION (TRUSTED ROUTER PATTERN)
    // ========================================================================
    
    /// @notice Resolves the actual end-user behind a swap
    /// @dev Implements the Trusted Router Pattern from the Uniswap v4 Hook Security Standards.
    ///
    ///      In Uniswap v4, the `sender` parameter in hook callbacks is the ROUTER contract,
    ///      not the end-user. Using `tx.origin` to identify users is unreliable because:
    ///      - ERC-4337 Smart Accounts use bundlers as tx.origin
    ///      - Bundled/batched transactions have different tx.origin than expected
    ///      - Meta-transactions relay through a different EOA
    ///
    ///      Resolution order:
    ///      1. If sender is a trusted router → call IMsgSender(sender).msgSender()
    ///      2. If the call fails or sender is untrusted → fall back to tx.origin
    ///
    ///      The hook never reverts during resolution — observation-only safety.
    ///
    /// @param sender The router address (from PoolManager callback)
    /// @return swapper The resolved end-user address
    function _resolveSwapper(address sender) internal returns (address swapper) {
        if (trustedRouters[sender]) {
            // Trusted router: query the authenticated user
            try IMsgSender(sender).msgSender() returns (address user) {
                if (user != address(0)) {
                    return user;
                }
            } catch {
                // Router failed to return user — fall through to tx.origin
            }
        }
        
        // Fallback: use tx.origin (safe for EOA swaps, unreliable for Smart Accounts)
        emit SwapperFallbackToTxOrigin(sender, tx.origin);
        return tx.origin;
    }
    
    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    /// @notice External function to decode referrer (for try/catch)
    /// @dev Used internally to handle malformed hookData gracefully
    /// @param hookData The encoded hook data
    /// @return referrer The decoded referrer address
    function decodeReferrer(bytes calldata hookData) external pure returns (address) {
        return abi.decode(hookData, (address));
    }
    
    /// @notice Gets the pool ID as bytes32
    /// @return The pool ID
    function getPoolId() external view returns (bytes32) {
        return poolId;
    }
    
    /// @notice Checks if this hook is registered with the registry
    /// @return registered Whether this hook is authorized in the registry
    function isRegistered() external view returns (bool) {
        return registry.isAuthorizedHook(address(this));
    }
}

// ============================================================================
// POOL ID EXTENSION
// ============================================================================

/// @notice Extension to convert PoolId to bytes32
/// @dev Required for storage as mapping key
library PoolIdExtension {
    function toBytes32(PoolId poolId) internal pure returns (bytes32) {
        return PoolId.unwrap(poolId);
    }
}

// Using statement for the extension
using PoolIdExtension for PoolId;
