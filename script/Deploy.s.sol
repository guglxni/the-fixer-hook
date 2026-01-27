// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ReferralHook} from "../src/ReferralHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "./HookMiner.sol";

/// @title Deploy ReferralHook
/// @notice Deployment script for the ReferralHook contract
/// @dev Uses CREATE2 with salt mining to deploy at a valid hook address
contract DeployReferralHook is Script {
    
    /// @notice Main deployment function
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================
        
        // Load PoolManager address from environment
        address poolManager = vm.envAddress("POOL_MANAGER");
        require(poolManager != address(0), "POOL_MANAGER not set");
        
        // Load deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("PoolManager address:", poolManager);
        
        // ====================================================================
        // ADDRESS MINING
        // ====================================================================
        
        // ReferralHook only needs afterSwap permission (bit 7 = 0x80)
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        console.log("Required flags:", uint256(flags));
        
        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(poolManager);
        
        // Find valid hook address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            flags,
            type(ReferralHook).creationCode,
            constructorArgs
        );
        
        console.log("Computed hook address:", hookAddress);
        console.log("Using salt:", vm.toString(salt));
        
        // Verify address has correct permission bits
        require(
            uint160(hookAddress) & flags == flags,
            "Invalid hook address"
        );
        
        // ====================================================================
        // DEPLOYMENT
        // ====================================================================
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy using CREATE2 with computed salt
        ReferralHook hook = new ReferralHook{salt: salt}(
            IPoolManager(poolManager)
        );
        
        // Verify deployment address matches
        require(
            address(hook) == hookAddress,
            "Deployed address mismatch"
        );
        
        vm.stopBroadcast();
        
        // ====================================================================
        // VERIFICATION
        // ====================================================================
        
        console.log("");
        console.log("=== Deployment Successful ===");
        console.log("ReferralHook deployed at:", address(hook));
        console.log("Token name:", hook.name());
        console.log("Token symbol:", hook.symbol());
        console.log("Reward amount:", hook.REWARD_AMOUNT());
        
        // Verify permissions
        Hooks.Permissions memory perms = hook.getHookPermissions();
        require(perms.afterSwap, "afterSwap permission not set");
        console.log("afterSwap permission: enabled");
    }
}

/// @title Verify ReferralHook
/// @notice Post-deployment verification script
contract VerifyReferralHook is Script {
    
    function run() external view {
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        
        ReferralHook hook = ReferralHook(hookAddress);
        
        console.log("=== Hook Verification ===");
        console.log("Address:", hookAddress);
        console.log("Name:", hook.name());
        console.log("Symbol:", hook.symbol());
        console.log("Decimals:", hook.decimals());
        console.log("Reward Amount:", hook.REWARD_AMOUNT());
        console.log("Total Supply:", hook.totalSupply());
        
        Hooks.Permissions memory perms = hook.getHookPermissions();
        console.log("");
        console.log("=== Permissions ===");
        console.log("afterSwap:", perms.afterSwap);
        console.log("beforeSwap:", perms.beforeSwap);
        console.log("afterSwapReturnDelta:", perms.afterSwapReturnDelta);
    }
}
