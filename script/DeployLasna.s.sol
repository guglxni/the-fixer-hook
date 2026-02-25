// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";
import {FixerCredential} from "../src/FixerCredential.sol";
import {IFixerRegistry} from "../src/interfaces/IFixerRegistry.sol";

/// @title DeployLasna
/// @notice Live testnet deployment: Registry + Proxy + Extension + Credential on Reactive Lasna
/// @dev No FixerHookV2 — Lasna has no Uniswap v4 PoolManager.
///      Lasna is a reactive execution layer; hooks are deployed on origin chains
///      (Base/Arb/Unichain Sepolia) and monitored via Reactive Contracts on Lasna.
///
/// Environment Variables:
///   PRIVATE_KEY              - Deployer private key (must have lREACT on Lasna)
///   SECURITY_COUNCIL         - Multisig for emergencies (default: deployer)
///   GOVERNANCE               - DAO governance address (default: address(0))
///
/// Usage:
///   forge script script/DeployLasna.s.sol \
///     --rpc-url lasna --broadcast -vvvv
contract DeployLasna is Script {
    // ====================================================================
    // LASNA TESTNET CONSTANTS
    // ====================================================================

    /// @dev Reactive Network system contract (same on Lasna and Mainnet)
    address constant REACTIVE_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000fffFfF;

    /// @dev Callback Proxy on Lasna — used by Reactive Contracts to verify callbacks
    address constant CALLBACK_PROXY = 0x0000000000000000000000000000000000fffFfF;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        console.log("=== FixerHook Protocol - Lasna (Reactive Network) Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID: 5318007 (Lasna Testnet)");
        console.log("Note: No PoolManager on Lasna - FixerHookV2 skipped");

        vm.startBroadcast(deployerPrivateKey);

        address proxy = _deployRegistry(deployer, securityCouncil, governance);
        address credential = _deployCredential(proxy, deployer);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================");
        console.log("  LASNA (REACTIVE) DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Registry Proxy: ", proxy);
        console.log("Credential NFT: ", credential);
        console.log("FixerHookV2:     SKIPPED (no PoolManager on Lasna)");
        console.log("==========================================");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Deploy Reactive Contracts to monitor origin chain events");
        console.log("  2. Register hooks from origin chains (Base/Arb/Unichain Sepolia)");
        console.log("  3. Set up cross-chain callbacks via Reactive system contract");
    }

    function _deployRegistry(
        address deployer,
        address securityCouncil,
        address governance
    ) internal returns (address) {
        // Deploy FixerLib via CREATE2 (deterministic address)
        // FixerLib is linked at compile time, deployed automatically by Foundry

        // Deploy implementation
        FixerRegistryUpgradeable impl = new FixerRegistryUpgradeable();
        console.log("[A1] Implementation:", address(impl));

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (deployer, securityCouncil, governance)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("[A2] Proxy:", address(proxy));

        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));
        require(registry.owner() == deployer, "Owner mismatch");
        require(registry.VERSION() == 2_006_000, "Version mismatch");

        // Initialize v4 (ERC-8004 Trustless Agents) — registries set to address(0)
        // until real registries are deployed on this chain
        registry.reinitializeV4(address(0), address(0), address(0));
        registry.reinitializeV5();

        // Deploy extension (Agent Infrastructure Stack + EIP-3009)
        FixerRegistryExtension ext = new FixerRegistryExtension();
        registry.setExtension(address(ext));
        console.log("[A3] Extension:", address(ext));
        console.log("[A4] Registry OK: FIX token, v2.6.0 (Agent Infrastructure Stack)");

        return address(proxy);
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
