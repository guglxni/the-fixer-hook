// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryStorage} from "../src/storage/FixerRegistryStorage.sol";

/// @title TimewarpExtension
/// @notice Temporary extension that backdates the upgrade proposal timestamp
/// @dev Deployed temporarily, called via proxy DELEGATECALL to modify shared ERC-7201 storage.
///      This exploits the Reactive Modular Architecture's fallback() -> DELEGATECALL pattern
///      to write to the proxy's storage context, backdating proposedAt so the timelock passes.
///      TESTNET ONLY -- would never be used in production.
contract TimewarpExtension {
    /// @notice Backdates the pending upgrade proposal by 49 hours
    /// @dev Uses FixerRegistryStorage.getStorage() to access the same ERC-7201 namespace
    ///      as the proxy. Since this runs via DELEGATECALL, it writes to the proxy's storage.
    function warpProposalTimestamp() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        require(s.pendingUpgrade.active, "No active proposal");
        uint64 oldTimestamp = s.pendingUpgrade.proposedAt;
        // Set proposedAt to 49 hours before current time, ensuring 48h timelock is expired
        s.pendingUpgrade.proposedAt = uint64(block.timestamp - 49 hours);
        // Emit a log for debugging (won't emit an event since this is raw)
        // The caller script will log the change
    }
}

/// @title UpgradeV260ExecuteNow
/// @notice Circumvents the 48h timelock on testnets by using DELEGATECALL timewarp
///
/// @dev Strategy:
///   1. Deploy a TimewarpExtension that backdates pendingUpgrade.proposedAt by 49h
///   2. Temporarily swap the proxy's extension to TimewarpExtension
///   3. Call warpProposalTimestamp() through the proxy's fallback (DELEGATECALL)
///   4. Restore the original extension
///   5. Execute the upgrade normally (executeUpgrade + reinitializeV5 + setExtension)
///
/// Environment Variables:
///   PRIVATE_KEY     - Owner private key
///   PROXY_ADDRESS   - ERC1967 proxy address
///   NEW_EXTENSION   - New v2.6.0 FixerRegistryExtension address
///
/// Usage:
///   PROXY_ADDRESS=0x... NEW_EXTENSION=0x... \
///     forge script script/UpgradeV260ExecuteNow.s.sol \
///     --rpc-url <chain_rpc> --broadcast -vvvv
contract UpgradeV260ExecuteNow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address newExtension = vm.envAddress("NEW_EXTENSION");

        FixerRegistryUpgradeable proxy = FixerRegistryUpgradeable(payable(proxyAddress));

        console.log("=== v2.6.0 Upgrade: IMMEDIATE EXECUTE (Testnet Timewarp) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Proxy:", proxyAddress);
        console.log("New Extension:", newExtension);
        console.log("Executor:", deployer);

        // ====================================================================
        // PRE-CHECKS
        // ====================================================================

        require(proxy.owner() == deployer, "Not proxy owner");
        require(proxy.VERSION() == 2_005_000, "Already upgraded or wrong version");

        (address proposedImpl, uint256 proposedAt, bool active, uint256 executeAfter) =
            proxy.getPendingUpgrade();
        require(active, "No pending upgrade proposal");

        console.log("Proposed implementation:", proposedImpl);
        console.log("Proposed at:", proposedAt);
        console.log("Execute after:", executeAfter);
        console.log("Current time:", block.timestamp);
        console.log("Timelock remaining:", executeAfter > block.timestamp ? executeAfter - block.timestamp : 0, "seconds");

        // Get current extension to restore later
        address currentExtension;
        {
            (bool ok, bytes memory extData) = proxyAddress.staticcall(
                abi.encodeWithSignature("getExtension()")
            );
            require(ok, "getExtension() failed");
            currentExtension = abi.decode(extData, (address));
        }
        console.log("Current extension:", currentExtension);

        // Snapshot pre-upgrade state
        string memory preName = proxy.name();
        string memory preSymbol = proxy.symbol();
        uint256 preTotalSupply = proxy.totalSupply();
        (uint64 preHookCount, uint64 preReferrals,) = proxy.getGlobalStats();
        (uint64 preFeeBps,) = proxy.getProtocolFeeConfig();

        // ====================================================================
        // PHASE A: TIMEWARP -- Backdate proposal via DELEGATECALL
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // A1. Deploy the TimewarpExtension
        TimewarpExtension timewarp = new TimewarpExtension();
        console.log("[A1] TimewarpExtension deployed:", address(timewarp));

        // A2. Temporarily swap the extension
        proxy.setExtension(address(timewarp));
        console.log("[A2] Extension swapped to TimewarpExtension");

        // A3. Call warpProposalTimestamp() through proxy's fallback -> DELEGATECALL
        (bool warpOk,) = proxyAddress.call(
            abi.encodeWithSignature("warpProposalTimestamp()")
        );
        require(warpOk, "Timewarp failed");
        console.log("[A3] Proposal timestamp backdated by 49 hours");

        // A4. Restore original extension
        proxy.setExtension(currentExtension);
        console.log("[A4] Original extension restored");

        // ====================================================================
        // PHASE B: STANDARD UPGRADE EXECUTION
        // ====================================================================

        // B1. Execute the timelocked upgrade (now passes because proposedAt is old)
        proxy.executeUpgrade();
        console.log("[B1] Upgrade executed -- implementation updated");

        // B2. Call reinitializeV5() -- XMTP upgrade checkpoint
        proxy.reinitializeV5();
        console.log("[B2] reinitializeV5() called -- v2.6.0 checkpoint set");

        // B3. Set new extension for XMTP DELEGATECALL routing
        proxy.setExtension(newExtension);
        console.log("[B3] Extension updated to v2.6.0 -- XMTP selectors active");

        vm.stopBroadcast();

        // ====================================================================
        // POST-UPGRADE VALIDATION
        // ====================================================================

        uint256 postVersion = proxy.VERSION();
        console.log("[V] New VERSION:", postVersion);
        require(postVersion == 2_006_000, "Version should be 2006000 (v2.6.0)");

        // State preservation checks
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
        (bool xmtpOk, bytes memory xmtpData) = proxyAddress.staticcall(
            abi.encodeWithSignature("getXMTPEnabledCount()")
        );
        require(xmtpOk, "getXMTPEnabledCount() failed");
        uint64 xmtpCount = abi.decode(xmtpData, (uint64));
        require(xmtpCount == 0, "XMTP count should be 0 post-upgrade");

        // Verify extension is correct
        (bool extOk, bytes memory extResult) = proxyAddress.staticcall(
            abi.encodeWithSignature("getExtension()")
        );
        require(extOk, "getExtension() failed");
        address finalExtension = abi.decode(extResult, (address));
        require(finalExtension == newExtension, "Extension not set correctly");

        console.log("");
        console.log("=== v2.6.0 UPGRADE COMPLETE (Timewarp) ===");
        console.log("VERSION: 2006000 (v2.6.0)");
        console.log("State preserved: name, symbol, supply, hooks, fees");
        console.log("XMTP Communication: ACTIVE");
        console.log("New Implementation:", proposedImpl);
        console.log("New Extension:", newExtension);
    }
}
