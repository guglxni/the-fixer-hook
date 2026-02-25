// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";

/// @title DeployX402
/// @notice Deploys FixerRegistryUpgradeable v2.4.0 (ERC-8004 Trustless Agents)
/// @dev Two modes:
///   Mode A — Fresh deployment (proxy + implementation)
///   Mode B — Upgrade existing proxy to v2.4.0 implementation
///
/// Features in v2.4.0:
///   - ERC-8004 permissionless agent registration (NFT ownership proof)
///   - Reputation-derived bonus tiers (0-5000 BPS from ERC-8004 scores)
///   - Reputation cache with configurable TTL
///   - Zero external calls on hot path (recordReferral)
///   - EIP-3009 transferWithAuthorization (x402-compatible token transfers)
///   - EIP-712 typed data
///
/// Environment Variables:
///   PRIVATE_KEY          - Deployer private key
///   SECURITY_COUNCIL     - Multisig address for emergencies
///   GOVERNANCE           - DAO governance address (optional)
///   PROXY_ADDRESS        - (Mode B only) existing proxy to upgrade
///   IDENTITY_REGISTRY    - (optional) ERC-8004 Identity Registry address
///   REPUTATION_REGISTRY  - (optional) ERC-8004 Reputation Registry address
///   VALIDATION_REGISTRY  - (optional) ERC-8004 Validation Registry address
///
/// Usage (fresh deploy):
///   forge script script/DeployX402.s.sol --rpc-url $RPC_URL --broadcast
///
/// Usage (upgrade existing):
///   PROXY_ADDRESS=0x... forge script script/DeployX402.s.sol:UpgradeToERC8004 --rpc-url $RPC_URL --broadcast
contract DeployX402 is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        // ERC-8004 registries — default to address(0) until deployed on-chain
        address identityRegistry = vm.envOr("IDENTITY_REGISTRY", address(0));
        address reputationRegistry = vm.envOr("REPUTATION_REGISTRY", address(0));
        address validationRegistry = vm.envOr("VALIDATION_REGISTRY", address(0));

        console.log("=== FixerRegistryUpgradeable v2.4.0 (ERC-8004) Fresh Deploy ===");
        console.log("Deployer:", deployer);
        console.log("Security Council:", securityCouncil);
        console.log("Governance:", governance);

        // ====================================================================
        // DEPLOYMENT
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy v2.4.0 implementation
        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        console.log("Implementation v2.4.0 deployed:", address(implementation));

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

        // 4. Initialize v4 (ERC-8004 Trustless Agents)
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));
        registry.reinitializeV4(identityRegistry, reputationRegistry, validationRegistry);

        // 5. Verify initialization
        require(registry.owner() == deployer, "Owner mismatch");
        require(registry.VERSION() == 2_006_000, "Version mismatch");

        (uint64 feeBps, uint64 maxFeeBps) = registry.getProtocolFeeConfig();
        require(feeBps == 500, "Fee not 5%");
        require(maxFeeBps == 1000, "Max fee not 10%");

        console.log("VERSION:", registry.VERSION());
        console.log("Token name:", registry.name());
        console.log("Token symbol:", registry.symbol());
        console.log("Protocol Fee (bps):", feeBps);
        console.log("Max Protocol Fee (bps):", maxFeeBps);
        console.log("ERC-8004 Identity:", identityRegistry);
        console.log("ERC-8004 Reputation:", reputationRegistry);
        console.log("ERC-8004 Validation:", validationRegistry);

        vm.stopBroadcast();

        // ====================================================================
        // OUTPUT
        // ====================================================================

        console.log("");
        console.log("=== v2.4.0 Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (use this):", address(proxy));
        console.log("");
        console.log("Next steps:");
        console.log("  1. Set FIXER_REGISTRY=", address(proxy));
        console.log("  2. Deploy FixerHookV2 pointing to this registry");
        console.log("  3. Deploy ERC-8004 registries and call setERC8004Registries()");
        console.log("  4. Configure x402 RaaS server with REGISTRY_ADDRESS");
    }
}

/// @title UpgradeToERC8004
/// @notice Upgrades existing FixerRegistryUpgradeable proxy from v2.3.x to v2.4.0
/// @dev Requires PROXY_ADDRESS env var pointing to existing proxy
///      Calls upgradeToAndCall with reinitializeV4() for ERC-8004 setup
contract UpgradeToERC8004 is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        // ERC-8004 registries — default to address(0) until deployed on-chain
        address identityRegistry = vm.envOr("IDENTITY_REGISTRY", address(0));
        address reputationRegistry = vm.envOr("REPUTATION_REGISTRY", address(0));
        address validationRegistry = vm.envOr("VALIDATION_REGISTRY", address(0));

        console.log("=== FixerRegistryUpgradeable v2.3.x -> v2.4.0 Upgrade ===");
        console.log("Deployer:", deployer);
        console.log("Proxy:", proxyAddress);

        FixerRegistryUpgradeable existing = FixerRegistryUpgradeable(payable(proxyAddress));
        uint256 oldVersion = existing.VERSION();
        console.log("Current VERSION:", oldVersion);
        require(oldVersion < 2_004_000, "Already at v2.4.0+");

        // ====================================================================
        // UPGRADE
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new v2.4.0 implementation
        FixerRegistryUpgradeable newImplementation = new FixerRegistryUpgradeable();
        console.log("New implementation deployed:", address(newImplementation));

        // 2. Prepare reinitializer call for v4 (initializes ERC-8004 registries)
        bytes memory reinitData = abi.encodeCall(
            FixerRegistryUpgradeable.reinitializeV4,
            (identityRegistry, reputationRegistry, validationRegistry)
        );

        // 3. Upgrade proxy to new implementation + call reinitializer
        existing.upgradeToAndCall(address(newImplementation), reinitData);

        // 4. Verify upgrade
        require(existing.VERSION() == 2_006_000, "Upgrade failed");
        console.log("Upgraded to VERSION:", existing.VERSION());
        console.log("ERC-8004 Identity:", identityRegistry);
        console.log("ERC-8004 Reputation:", reputationRegistry);
        console.log("ERC-8004 Validation:", validationRegistry);

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
        console.log("ERC-8004 features now active:");
        console.log("  - Permissionless agent registration via NFT ownership");
        console.log("  - Reputation-derived bonus tiers (0-5000 BPS)");
        console.log("  - Reputation cache with configurable TTL");
        console.log("  - Referral feedback submission (giveFeedback)");
        console.log("  - Zero external calls on hot path (recordReferral)");
    }
}
