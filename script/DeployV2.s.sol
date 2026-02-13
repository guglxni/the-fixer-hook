// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerHookV2} from "../src/FixerHookV2.sol";
import {FixerRegistry} from "../src/FixerRegistry.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "./HookMiner.sol";
import {IFixerRegistry} from "../src/interfaces/IFixerRegistry.sol";

/// @title Deploy FixerHook V2
/// @notice Deployment script for the FixerHook V2 architecture (Registry + Hook)
contract DeployFixerHookV2 is Script {

    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================
        
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Example Pool Configuration (Adjust as needed)
        // Ideally, these come from env or are passed in
        Currency currency0 = Currency.wrap(vm.envOr("TOKEN0", address(0)));
        Currency currency1 = Currency.wrap(vm.envOr("TOKEN1", address(0)));
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // ====================================================================
        // 1. DEPLOY REGISTRY
        // ====================================================================
        
        FixerRegistry registry = new FixerRegistry(deployer);
        console.log("FixerRegistry deployed at:", address(registry));

        // ====================================================================
        // 2. MINE & DEPLOY HOOK
        // ====================================================================
        
        // FixerHookV2 takes individual pool config fields (not PoolKey) to avoid
        // the circular dependency where PoolKey.hooks needs the hook's own address.
        // The hook constructs the PoolKey internally using address(this).
        
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        if (Currency.unwrap(currency0) == address(0)) {
            console.log("Please set TOKEN0 and TOKEN1 env vars for V2 deployment.");
            vm.stopBroadcast();
            return;
        }

        // Quote token index (0 or 1)
        uint256 quoteTokenIndex = 1; // Default to token1 (usually stable)

        // Constructor args match the new signature:
        // (IPoolManager, IFixerRegistry, Currency, Currency, uint24, int24, uint256)
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager),
            registry,
            currency0,
            currency1,
            fee,
            tickSpacing,
            quoteTokenIndex
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            flags,
            type(FixerHookV2).creationCode,
            constructorArgs
        );
        
        console.log("Mined Hook Address:", hookAddress);

        FixerHookV2 hook = new FixerHookV2{salt: salt}(
            IPoolManager(poolManager),
            registry,
            currency0,
            currency1,
            fee,
            tickSpacing,
            quoteTokenIndex
        );
        
        require(address(hook) == hookAddress, "Hook address mismatch");

        // ====================================================================
        // 3. REGISTER HOOK
        // ====================================================================
        
        // The hook constructs its poolId internally using address(this),
        // so the stored ID correctly matches the actual Uniswap v4 pool.
        bytes32 storedPoolId = hook.getPoolId();
        
        registry.registerHook(address(hook), storedPoolId);
        console.log("Hook registered in registry for Pool ID:", vm.toString(storedPoolId));
        
        // ====================================================================
        // 4. CONFIGURE TRUSTED ROUTERS (Optional)
        // ====================================================================
        
        // Add trusted routers for ERC-4337 compatible user identification.
        // Trusted routers must implement IMsgSender interface.
        // If no trusted router is set, the hook falls back to tx.origin.
        //
        // Example (uncomment and set the router address):
        // address swapRouter = vm.envOr("SWAP_ROUTER", address(0));
        // if (swapRouter != address(0)) {
        //     hook.setTrustedRouter(swapRouter, true);
        //     console.log("Trusted router added:", swapRouter);
        // }
        
        vm.stopBroadcast();
    }
}
