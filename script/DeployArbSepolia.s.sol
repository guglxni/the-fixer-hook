// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerHookV2} from "../src/FixerHookV2.sol";
import {FixerCredential} from "../src/FixerCredential.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IFixerRegistry} from "../src/interfaces/IFixerRegistry.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "./HookMiner.sol";

/// @title DeployArbSepolia
/// @notice Live testnet deployment: Registry + Proxy + HookV2 + Credential on Arbitrum Sepolia
/// @dev Uses real Arbitrum Sepolia USDC and WETH — no mocks
///
/// Environment Variables:
///   PRIVATE_KEY              - Deployer private key (must have Arb Sepolia ETH)
///   SECURITY_COUNCIL         - Multisig for emergencies (default: deployer)
///   GOVERNANCE               - DAO governance address (default: address(0))
///
/// Usage:
///   forge script script/DeployArbSepolia.s.sol \
///     --rpc-url arb_sepolia --broadcast --verify -vvvv
contract DeployArbSepolia is Script {
    // ====================================================================
    // ARBITRUM SEPOLIA CONSTANTS (live testnet addresses)
    // ====================================================================

    address constant POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant WETH = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34;
    uint256 constant QUOTE_TOKEN_INDEX = 0; // USDC is currency0 (lower address)
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // Foundry deterministic CREATE2 deployer used by `new Contract{salt}()`
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        console.log("=== FixerHook Protocol - Arbitrum Sepolia Live Deployment ===");
        console.log("Deployer:", deployer);
        console.log("USDC/WETH pool on PoolManager:", POOL_MANAGER);

        vm.startBroadcast(deployerPrivateKey);

        address proxy = _deployRegistry(deployer, securityCouncil, governance);
        address hook = _deployHook(deployer, proxy);
        _registerHook(proxy, hook);
        address credential = _deployCredential(proxy, deployer);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================");
        console.log("  ARBITRUM SEPOLIA DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Registry Proxy: ", proxy);
        console.log("FixerHookV2:    ", hook);
        console.log("Credential NFT: ", credential);
        console.log("==========================================");
    }

    function _deployRegistry(
        address deployer,
        address securityCouncil,
        address governance
    ) internal returns (address) {
        FixerRegistryUpgradeable impl = new FixerRegistryUpgradeable();
        console.log("[A1] Implementation:", address(impl));

        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (deployer, securityCouncil, governance)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("[A2] Proxy:", address(proxy));

        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(address(proxy));
        require(registry.owner() == deployer, "Owner mismatch");
        require(registry.VERSION() == 2_003_000, "Version mismatch");
        console.log("[A3] Registry OK: FIX token, v2.3.0");

        return address(proxy);
    }

    function _deployHook(
        address,
        address registryProxy
    ) internal returns (address) {
        Currency currency0 = Currency.wrap(USDC);
        Currency currency1 = Currency.wrap(WETH);
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER),
            IFixerRegistry(registryProxy),
            currency0,
            currency1,
            POOL_FEE,
            TICK_SPACING,
            QUOTE_TOKEN_INDEX
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, flags, type(FixerHookV2).creationCode, constructorArgs
        );
        console.log("[B1] Mined hook address:", hookAddress);

        FixerHookV2 hook = new FixerHookV2{salt: salt}(
            IPoolManager(POOL_MANAGER),
            IFixerRegistry(registryProxy),
            currency0,
            currency1,
            POOL_FEE,
            TICK_SPACING,
            QUOTE_TOKEN_INDEX
        );

        require(address(hook) == hookAddress, "Hook address mismatch");
        console.log("[B2] FixerHookV2:", address(hook));
        return address(hook);
    }

    function _registerHook(address registryProxy, address hook) internal {
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(registryProxy);
        bytes32 poolId = FixerHookV2(hook).getPoolId();
        registry.registerHook(hook, poolId);
        console.log("[C1] Hook registered, Pool ID:", vm.toString(poolId));
    }

    function _deployCredential(
        address registryProxy,
        address owner
    ) internal returns (address) {
        FixerCredential credential = new FixerCredential(
            IFixerRegistry(registryProxy), owner
        );
        console.log("[D1] FixerCredential:", address(credential));
        return address(credential);
    }
}
