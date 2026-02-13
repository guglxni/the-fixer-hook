// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";

/// @title DeployX402
/// @notice Deploys FixerRegistryUpgradeable v2.3.0 (x402 agent enhancements)
/// @dev Two modes:
///   Mode A — Fresh deployment (proxy + implementation)
///   Mode B — Upgrade existing proxy to v2.3.0 implementation
///
/// New features in v2.3.0:
///   - x402 Agent Registry (registerAgent, deregisterAgent, profiles)
///   - Referral Delegation (agent → agent forwarding)
///   - EIP-3009 transferWithAuthorization (x402-compatible token transfers)
///   - Agent bonus multiplier on top of tier multiplier
///   - EIP-712 typed data (initialized for transfer authorization)
///
/// Environment Variables:
///   PRIVATE_KEY          - Deployer private key
///   SECURITY_COUNCIL     - Multisig address for emergencies
///   GOVERNANCE           - DAO governance address (optional)
///   PROXY_ADDRESS        - (Mode B only) existing proxy to upgrade
///
/// Usage (fresh deploy):
///   forge script script/DeployX402.s.sol --rpc-url $RPC_URL --broadcast
///
/// Usage (upgrade existing):
///   PROXY_ADDRESS=0x... forge script script/DeployX402.s.sol:UpgradeToX402 --rpc-url $RPC_URL --broadcast
contract DeployX402 is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        console.log("=== FixerRegistryUpgradeable v2.3.0 (x402) Fresh Deploy ===");
        console.log("Deployer:", deployer);
        console.log("Security Council:", securityCouncil);
        console.log("Governance:", governance);

        // ====================================================================
        // DEPLOYMENT
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy v2.3.0 implementation
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        console.log("Implementation v2.3.0 deployed:", address(implementation));

        // 2. Encode initialize() — this sets up EIP-712 from the start
        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (deployer, securityCouncil, governance)
        );

        // 3. Deploy ERC1967 proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed:", address(proxy));

        // 4. Verify initialization
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(address(proxy));
        require(registry.owner() == deployer, "Owner mismatch");
        require(registry.VERSION() == 2_003_000, "Version mismatch");

        (uint64 feeBps, uint64 maxFeeBps) = registry.getProtocolFeeConfig();
        require(feeBps == 500, "Fee not 5%");
        require(maxFeeBps == 1000, "Max fee not 10%");

        console.log("VERSION:", registry.VERSION());
        console.log("Token name:", registry.name());
        console.log("Token symbol:", registry.symbol());
        console.log("Protocol Fee (bps):", feeBps);
        console.log("Max Protocol Fee (bps):", maxFeeBps);
        console.log("DOMAIN_SEPARATOR:", vm.toString(registry.DOMAIN_SEPARATOR()));
        console.log("Total Agents:", registry.getTotalAgents());

        vm.stopBroadcast();

        // ====================================================================
        // OUTPUT
        // ====================================================================

        console.log("");
        console.log("=== v2.3.0 Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (use this):", address(proxy));
        console.log("");
        console.log("Next steps:");
        console.log("  1. Set FIXER_REGISTRY=", address(proxy));
        console.log("  2. Deploy FixerHookV2 pointing to this registry");
        console.log("  3. Configure x402 RaaS server with REGISTRY_ADDRESS");
        console.log("  4. Configure MCP server with REGISTRY_ADDRESS");
    }
}

/// @title UpgradeToX402
/// @notice Upgrades existing FixerRegistryUpgradeable proxy from v2.2.x to v2.3.0
/// @dev Requires PROXY_ADDRESS env var pointing to existing proxy
///      Calls upgradeToAndCall with reinitializeV3() for EIP-712 setup
contract UpgradeToX402 is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        console.log("=== FixerRegistryUpgradeable v2.2.x -> v2.3.0 Upgrade ===");
        console.log("Deployer:", deployer);
        console.log("Proxy:", proxyAddress);

        FixerRegistryUpgradeable existing = FixerRegistryUpgradeable(proxyAddress);
        uint256 oldVersion = existing.VERSION();
        console.log("Current VERSION:", oldVersion);
        require(oldVersion < 2_003_000, "Already at v2.3.0+");

        // ====================================================================
        // UPGRADE
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new v2.3.0 implementation
        FixerRegistryUpgradeable newImplementation = new FixerRegistryUpgradeable();
        console.log("New implementation deployed:", address(newImplementation));

        // 2. Prepare reinitializer call for v3 (initializes EIP-712)
        bytes memory reinitData = abi.encodeCall(
            FixerRegistryUpgradeable.reinitializeV3,
            ()
        );

        // 3. Upgrade proxy to new implementation + call reinitializer
        existing.upgradeToAndCall(address(newImplementation), reinitData);

        // 4. Verify upgrade
        require(existing.VERSION() == 2_003_000, "Upgrade failed");
        console.log("Upgraded to VERSION:", existing.VERSION());
        console.log("DOMAIN_SEPARATOR:", vm.toString(existing.DOMAIN_SEPARATOR()));
        console.log("Total Agents:", existing.getTotalAgents());

        vm.stopBroadcast();

        // ====================================================================
        // OUTPUT
        // ====================================================================

        console.log("");
        console.log("=== Upgrade Summary ===");
        console.log("Proxy (unchanged):", proxyAddress);
        console.log("New implementation:", address(newImplementation));
        console.log("Version:", oldVersion, "->", existing.VERSION());
        console.log("");
        console.log("x402 features now active:");
        console.log("  - Agent registration (registerAgent/deregisterAgent)");
        console.log("  - Referral delegation (delegateReferral/revokeDelegation)");
        console.log("  - EIP-3009 transferWithAuthorization");
        console.log("  - Agent bonus multipliers");
    }
}
