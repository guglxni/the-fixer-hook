// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FixerRegistryUpgradeable} from "../src/FixerRegistryUpgradeable.sol";
import {FixerRegistryExtension} from "../src/FixerRegistryExtension.sol";

/// @title UpgradeV260
/// @notice UUPS upgrade: v2.5.0 -> v2.6.0 (Agent Infrastructure Stack -- XMTP Communication)
///
/// @dev This script performs the following steps on each chain:
///   1. Deploy new FixerRegistryUpgradeable implementation (v2.6.0)
///   2. Deploy new FixerRegistryExtension (with XMTP functions)
///   3. Call upgradeToAndCall(newImpl, reinitializeV5()) on the proxy
///   4. Call setExtension(newExtension) to route XMTP DELEGATECALL selectors
///   5. Validate: VERSION = 2_006_000, state preserved, XMTP counter = 0
///
/// What's new in v2.6.0:
///   - enableXMTP() / disableXMTP() / updateXMTPEndpoint() (on-chain XMTP identity)
///   - isXMTPEnabled() / getXMTPPublicKeyHash() / getXMTPEndpoint() / getXMTPEnabledCount()
///   - AgentProfile struct extended with xmtpEnabled, xmtpPublicKeyHash, xmtpEndpointUri
///   - reinitializeV5() checkpoint (no storage writes -- XMTP fields default to zero)
///
/// Environment Variables:
///   PRIVATE_KEY    - Owner private key (must own the proxy on each chain)
///   PROXY_ADDRESS  - Address of the deployed ERC1967 proxy on the target chain
///
/// Usage (per chain):
///   PROXY_ADDRESS=0x... forge script script/UpgradeV260.s.sol \
///     --rpc-url <chain_rpc> --broadcast --verify -vvvv
///
/// Chain-specific PROXY_ADDRESS values:
///   Unichain Sepolia: 0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9
///   Base Sepolia:     0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960
///   Arb Sepolia:      0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb
///   Lasna:            0xd2f11a95F1ca8cc94FB63926dc3A92655aAc6fF3
contract UpgradeV260 is Script {
    function run() external {
        // ====================================================================
        // CONFIGURATION
        // ====================================================================

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        FixerRegistryUpgradeable proxy = FixerRegistryUpgradeable(payable(proxyAddress));

        console.log("=== FixerRegistry v2.6.0 Upgrade (XMTP Communication) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Proxy:", proxyAddress);
        console.log("Upgrader:", deployer);

        // ====================================================================
        // PRE-UPGRADE CHECKS
        // ====================================================================

        require(proxy.owner() == deployer, "Not proxy owner");

        // Snapshot pre-upgrade state for validation
        uint256 preVersion = proxy.VERSION();
        string memory preName = proxy.name();
        string memory preSymbol = proxy.symbol();
        uint256 preTotalSupply = proxy.totalSupply();
        (uint64 preHookCount, uint64 preReferrals,) = proxy.getGlobalStats();
        (uint64 preFeeBps,) = proxy.getProtocolFeeConfig();

        // getTotalAgents() is on Extension (routed via fallback DELEGATECALL)
        uint64 preTotalAgents;
        {
            (bool ok, bytes memory d) = proxyAddress.staticcall(
                abi.encodeWithSignature("getTotalAgents()")
            );
            require(ok, "getTotalAgents() failed");
            preTotalAgents = abi.decode(d, (uint64));
        }

        console.log("Current VERSION:", preVersion);
        console.log("Total Supply:", preTotalSupply);
        console.log("Hook Count:", uint256(preHookCount));
        console.log("Total Agents:", uint256(preTotalAgents));

        require(preVersion == 2_005_000, "Expected v2.5.0 (2005000)");

        // ====================================================================
        // DEPLOY NEW CONTRACTS
        // ====================================================================

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new implementation with XMTP support
        FixerRegistryUpgradeable newImpl = new FixerRegistryUpgradeable();
        console.log("[1] New implementation:", address(newImpl));

        // 2. Deploy new extension with XMTP functions
        FixerRegistryExtension newExtension = new FixerRegistryExtension();
        console.log("[2] New extension:", address(newExtension));

        // 3. UUPS upgrade with reinitializeV5() call
        //    reinitializeV5 is a reinitializer(5) that sets the upgrade checkpoint.
        //    XMTP fields default to zero -- no storage writes needed.
        bytes memory reinitData = abi.encodeCall(
            FixerRegistryUpgradeable.reinitializeV5,
            ()
        );
        proxy.upgradeToAndCall(address(newImpl), reinitData);
        console.log("[3] Upgraded implementation + called reinitializeV5()");

        // 4. Set new extension for XMTP DELEGATECALL routing
        proxy.setExtension(address(newExtension));
        console.log("[4] Extension updated for XMTP selectors");

        vm.stopBroadcast();

        // ====================================================================
        // POST-UPGRADE VALIDATION
        // ====================================================================

        uint256 postVersion = proxy.VERSION();
        console.log("[5] New VERSION:", postVersion);
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

        uint64 postTotalAgents;
        {
            (bool ok2, bytes memory d2) = proxyAddress.staticcall(
                abi.encodeWithSignature("getTotalAgents()")
            );
            require(ok2, "getTotalAgents() failed post-upgrade");
            postTotalAgents = abi.decode(d2, (uint64));
        }
        require(postTotalAgents == preTotalAgents, "Agent count changed");

        // XMTP-specific: counter should be 0 (no agents have enabled XMTP yet)
        // Note: getXMTPEnabledCount() is on the Extension, called via DELEGATECALL
        // We call it through the proxy (which will route to extension via fallback)
        (bool success, bytes memory data) = proxyAddress.staticcall(
            abi.encodeWithSignature("getXMTPEnabledCount()")
        );
        require(success, "getXMTPEnabledCount() failed");
        uint64 xmtpCount = abi.decode(data, (uint64));
        require(xmtpCount == 0, "XMTP count should be 0 post-upgrade");
        console.log("[6] XMTP enabled count:", uint256(xmtpCount));

        console.log("");
        console.log("=== v2.6.0 Upgrade Successful ===");
        console.log("State preserved: name, symbol, supply, hooks, fees, agents");
        console.log("New capabilities: XMTP Communication (enableXMTP, disableXMTP, etc.)");
        console.log("New implementation:", address(newImpl));
        console.log("New extension:", address(newExtension));
    }
}
