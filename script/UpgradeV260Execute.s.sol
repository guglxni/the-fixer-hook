// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";

/// @title UpgradeV260Execute
/// @notice Phase 2 of 2: Execute upgrade v2.5.0 -> v2.6.0 after 48h timelock
///
/// @dev Must be run after Phase 1 (UpgradeV260Propose.s.sol) and the 48h timelock.
///
///   Steps:
///     1. Call executeUpgrade() -- finalizes the UUPS proxy upgrade
///     2. Call reinitializeV5() -- sets the v2.6.0 checkpoint
///     3. Call setExtension(newExtension) -- enables XMTP DELEGATECALL routing
///     4. Validate state preservation and VERSION = 2_006_000
///
/// Environment Variables:
///   PRIVATE_KEY     - Owner private key
///   PROXY_ADDRESS   - ERC1967 proxy address
///   NEW_EXTENSION   - New FixerRegistryExtension address (from Phase 1 output)
///
/// Usage:
///   PROXY_ADDRESS=0x... NEW_EXTENSION=0x... \
///     forge script script/UpgradeV260Execute.s.sol \
///     --rpc-url <chain_rpc> --broadcast -vvvv
contract UpgradeV260Execute is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address newExtension = vm.envAddress("NEW_EXTENSION");

        FixerRegistryUpgradeable proxy = FixerRegistryUpgradeable(payable(proxyAddress));

        console.log("=== v2.6.0 Upgrade Phase 2: EXECUTE ===");
        console.log("Chain ID:", block.chainid);
        console.log("Proxy:", proxyAddress);
        console.log("New Extension:", newExtension);
        console.log("Executor:", deployer);

        // ====================================================================
        // PRE-EXECUTE CHECKS
        // ====================================================================

        require(proxy.owner() == deployer, "Not proxy owner");
        require(proxy.VERSION() == 2_005_000, "Already upgraded or wrong version");

        // Verify timelock proposal is active and ready
        (address proposedImpl, uint256 proposedAt, bool active, uint256 executeAfter) =
            proxy.getPendingUpgrade();
        require(active, "No pending upgrade proposal");
        require(block.timestamp >= executeAfter, "Timelock not expired yet");

        console.log("Proposed implementation:", proposedImpl);
        console.log("Proposed at:", proposedAt);
        console.log("Execute after:", executeAfter);
        console.log("Current time:", block.timestamp);

        // Snapshot pre-upgrade state
        string memory preName = proxy.name();
        string memory preSymbol = proxy.symbol();
        uint256 preTotalSupply = proxy.totalSupply();
        (uint64 preHookCount, uint64 preReferrals,) = proxy.getGlobalStats();
        (uint64 preFeeBps,) = proxy.getProtocolFeeConfig();

        // ====================================================================
        // EXECUTE UPGRADE
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Execute the timelocked upgrade (upgradeToAndCall with empty calldata)
        proxy.executeUpgrade();
        console.log("[1] Upgrade executed -- implementation updated");

        // 2. Call reinitializeV5() -- XMTP upgrade checkpoint
        proxy.reinitializeV5();
        console.log("[2] reinitializeV5() called -- v2.6.0 checkpoint set");

        // 3. Set new extension for XMTP DELEGATECALL routing
        proxy.setExtension(newExtension);
        console.log("[3] Extension updated -- XMTP selectors active");

        vm.stopBroadcast();

        // ====================================================================
        // POST-UPGRADE VALIDATION
        // ====================================================================

        uint256 postVersion = proxy.VERSION();
        console.log("[4] New VERSION:", postVersion);
        require(postVersion == 2_006_000, "Version should be 2006000 (v2.6.0)");

        // State preservation
        require(
            keccak256(bytes(proxy.name())) == keccak256(bytes(preName)),
            "Name changed"
        );
        require(
            keccak256(bytes(proxy.symbol())) == keccak256(bytes(preSymbol)),
            "Symbol changed"
        );
        require(proxy.totalSupply() == preTotalSupply, "Supply changed");

        (uint64 postHookCount, uint64 postReferrals,) = proxy.getGlobalStats();
        require(postHookCount == preHookCount, "Hook count changed");
        require(postReferrals == preReferrals, "Referral count changed");

        (uint64 postFeeBps,) = proxy.getProtocolFeeConfig();
        require(postFeeBps == preFeeBps, "Fee changed");

        // XMTP counter should be 0
        (bool success, bytes memory data) = proxyAddress.staticcall(
            abi.encodeWithSignature("getXMTPEnabledCount()")
        );
        require(success, "getXMTPEnabledCount() failed");
        uint64 xmtpCount = abi.decode(data, (uint64));
        require(xmtpCount == 0, "XMTP count should be 0 post-upgrade");

        console.log("");
        console.log("=== v2.6.0 UPGRADE COMPLETE ===");
        console.log("VERSION: 2006000 (v2.6.0)");
        console.log("State preserved: name, symbol, supply, hooks, fees");
        console.log("XMTP Communication: ACTIVE");
        console.log("New Implementation:", proposedImpl);
        console.log("New Extension:", newExtension);
    }
}
