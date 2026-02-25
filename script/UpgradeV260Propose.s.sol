// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";

/// @title UpgradeV260Propose
/// @notice Phase 1 of 2: Propose UUPS upgrade v2.5.0 -> v2.6.0 (XMTP Communication)
///
/// @dev Deploys new contracts and initiates the 48-hour timelock proposal.
///      After 48h, run UpgradeV260Execute.s.sol to complete the upgrade.
///
///   Phase 1 (this script):
///     1. Deploy new FixerRegistryUpgradeable implementation (v2.6.0)
///     2. Deploy new FixerRegistryExtension (with XMTP functions)
///     3. Call proposeUpgrade(newImpl) to start 48h timelock
///     4. Output addresses for Phase 2
///
///   Phase 2 (UpgradeV260Execute.s.sol):
///     1. Call executeUpgrade() (after 48h timelock expires)
///     2. Call reinitializeV5()
///     3. Call setExtension(newExtension)
///     4. Validate state preservation
///
/// Environment Variables:
///   PRIVATE_KEY    - Owner private key
///   PROXY_ADDRESS  - ERC1967 proxy address
///
/// Usage:
///   PROXY_ADDRESS=0x... forge script script/UpgradeV260Propose.s.sol \
///     --rpc-url <chain_rpc> --broadcast -vvvv
contract UpgradeV260Propose is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        FixerRegistryUpgradeable proxy = FixerRegistryUpgradeable(payable(proxyAddress));

        console.log("=== v2.6.0 Upgrade Phase 1: PROPOSE ===");
        console.log("Chain ID:", block.chainid);
        console.log("Proxy:", proxyAddress);
        console.log("Upgrader:", deployer);

        // Pre-checks
        require(proxy.owner() == deployer, "Not proxy owner");
        require(proxy.VERSION() == 2_005_000, "Expected v2.5.0");

        // Check no pending upgrade exists
        (, , bool active,) = proxy.getPendingUpgrade();
        require(!active, "Upgrade already pending -- cancel or execute first");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new implementation
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();
        console.log("[1] New implementation:", address(newImpl));

        // 2. Deploy new extension
        FixerRegistryExtension newExtension = new FixerRegistryExtension();
        console.log("[2] New extension:", address(newExtension));

        // 3. Propose upgrade (starts 48h timelock)
        proxy.proposeUpgrade(address(newImpl));
        console.log("[3] Upgrade proposed -- 48h timelock started");

        vm.stopBroadcast();

        // Display Phase 2 instructions
        console.log("");
        console.log("=== PHASE 1 COMPLETE ===");
        console.log("New Implementation:", address(newImpl));
        console.log("New Extension:", address(newExtension));
        console.log("");
        console.log(">>> SAVE THESE ADDRESSES <<<");
        console.log(">>> After 48h, run UpgradeV260Execute.s.sol with: <<<");
        console.log("  PROXY_ADDRESS=", proxyAddress);
        console.log("  NEW_EXTENSION=", address(newExtension));
    }
}
