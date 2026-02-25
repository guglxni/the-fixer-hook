// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";

/// @title DeployUpgradeable
/// @notice Deploys FixerRegistryUpgradeable behind an ERC1967 proxy
/// @dev Steps:
///   1. Deploy FixerRegistryUpgradeable implementation
///   2. Deploy ERC1967Proxy pointing to implementation
///   3. Call initialize() atomically via proxy constructor
///
/// Environment Variables:
///   PRIVATE_KEY          - Deployer private key
///   SECURITY_COUNCIL     - Multisig address for emergencies
///   GOVERNANCE           - DAO governance address (optional, can be address(0))
///
/// Usage:
///   forge script script/DeployUpgradeable.s.sol --rpc-url $RPC_URL --broadcast
contract DeployUpgradeable is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        console.log("=== FixerRegistryUpgradeable Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Security Council:", securityCouncil);
        console.log("Governance:", governance);

        // ====================================================================
        // DEPLOYMENT
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation contract
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        console.log("Implementation deployed:", address(implementation));

        // 2. Encode initialize() call data
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (deployer, securityCouncil, governance)
        );

        // 3. Deploy ERC1967 proxy (calls initialize atomically)
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed:", address(proxy));

        // 4. Verify initialization
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));
        require(registry.owner() == deployer, "Owner mismatch");
        require(keccak256(bytes(registry.name())) == keccak256("Fixer Token"), "Name mismatch");
        require(keccak256(bytes(registry.symbol())) == keccak256("FIX"), "Symbol mismatch");

        (uint64 feeBps, uint64 maxFeeBps) = registry.getProtocolFeeConfig();
        require(feeBps == 500, "Fee not 5%");
        require(maxFeeBps == 1000, "Max fee not 10%");

        console.log("VERSION:", registry.VERSION());
        console.log("Token name:", registry.name());
        console.log("Token symbol:", registry.symbol());
        console.log("Protocol Fee (bps):", feeBps);
        console.log("Max Protocol Fee (bps):", maxFeeBps);

        vm.stopBroadcast();

        // ====================================================================
        // OUTPUT
        // ====================================================================

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (use this):", address(proxy));
        console.log("");
        console.log("Proxy address (set as FIXER_REGISTRY):", address(proxy));
    }
}
