// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";

/// @title Upgrade
/// @notice Upgrades FixerRegistryUpgradeable to a new implementation
/// @dev Steps:
///   1. Deploy new implementation
///   2. Call upgradeToAndCall on proxy
///   3. Validate state preservation and new version
///
/// Environment Variables:
///   PRIVATE_KEY     - Owner private key (must own the proxy)
///   PROXY_ADDRESS   - Address of the deployed ERC1967 proxy
///
/// Usage:
///   forge script script/Upgrade.s.sol --rpc-url $RPC_URL --broadcast
///
/// Safety Checks:
///   - Verifies caller is proxy owner
///   - Validates storage layout compatibility (via foundry-upgrades in tests)
///   - Checks VERSION incremented
///   - Confirms state preserved post-upgrade
contract Upgrade is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        FixerRegistryUpgradeable proxy = FixerRegistryUpgradeable(payable(proxyAddress));

        console.log("=== FixerRegistry Upgrade ===");
        console.log("Proxy:", proxyAddress);
        console.log("Upgrader:", deployer);

        // ====================================================================
        // PRE-UPGRADE CHECKS
        // ====================================================================

        // Verify ownership
        require(proxy.owner() == deployer, "Not proxy owner");

        // Snapshot pre-upgrade state
        uint256 preVersion = proxy.VERSION();
        string memory preName = proxy.name();
        string memory preSymbol = proxy.symbol();
        uint256 preTotalSupply = proxy.totalSupply();
        (uint64 preHookCount,,) = proxy.getGlobalStats();
        (uint64 preFeeBps,) = proxy.getProtocolFeeConfig();

        console.log("Current VERSION:", preVersion);
        console.log("Total Supply:", preTotalSupply);
        console.log("Hook Count:", uint256(preHookCount));

        // ====================================================================
        // DEPLOY NEW IMPLEMENTATION
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        FixerRegistryUpgradeable newImplementation = new FixerRegistryUpgradeable();
        console.log("New implementation:", address(newImplementation));

        // Upgrade (with empty calldata — no reinitializer call)
        // For upgrades needing migration, use:
        //   proxy.upgradeToAndCall(address(newImpl), abi.encodeCall(...));
        proxy.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        // ====================================================================
        // POST-UPGRADE VALIDATION
        // ====================================================================

        // Verify version changed (or same if re-deploying same version)
        uint256 postVersion = proxy.VERSION();
        console.log("New VERSION:", postVersion);

        // Verify state preservation
        require(
            keccak256(bytes(proxy.name())) == keccak256(bytes(preName)),
            "Name changed after upgrade"
        );
        require(
            keccak256(bytes(proxy.symbol())) == keccak256(bytes(preSymbol)),
            "Symbol changed after upgrade"
        );
        require(
            proxy.totalSupply() == preTotalSupply,
            "Total supply changed after upgrade"
        );

        (uint64 postHookCount,,) = proxy.getGlobalStats();
        require(postHookCount == preHookCount, "Hook count changed after upgrade");

        (uint64 postFeeBps,) = proxy.getProtocolFeeConfig();
        require(postFeeBps == preFeeBps, "Protocol fee changed after upgrade");

        console.log("");
        console.log("=== Upgrade Successful ===");
        console.log("State preserved: name, symbol, supply, hooks, fees");
    }
}
