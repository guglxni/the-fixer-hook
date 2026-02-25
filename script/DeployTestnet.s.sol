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
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @title DeployTestnet
/// @notice Deploys the full Fixer Protocol v2.3 stack to a testnet
/// @dev Deploys in order:
///   1. Mock ERC20 tokens (if TOKEN0/TOKEN1 not provided)
///   2. FixerRegistryUpgradeable implementation + ERC1967 proxy
///   3. FixerHookV2 (CREATE2-mined for valid hook address)
///   4. Registers hook in registry
///   5. FixerCredential (optional)
///
/// Environment Variables:
///   PRIVATE_KEY          - Deployer private key (required)
///   POOL_MANAGER         - Uniswap v4 PoolManager address (required)
///   SECURITY_COUNCIL     - Multisig for emergencies (optional, defaults to deployer)
///   GOVERNANCE           - DAO governance address (optional, defaults to address(0))
///   TOKEN0               - Lower token address (optional, deploys mock if unset)
///   TOKEN1               - Higher token address (optional, deploys mock if unset)
///   POOL_FEE             - Pool fee in hundredths of a bip (optional, defaults to 3000)
///   TICK_SPACING         - Pool tick spacing (optional, defaults to 60)
///   QUOTE_TOKEN_INDEX    - Which token is quote: 0 or 1 (optional, defaults to 1)
///   DEPLOY_CREDENTIAL    - Deploy FixerCredential NFT (optional, defaults to true)
///
/// Usage:
///   forge script script/DeployTestnet.s.sol --rpc-url $RPC_URL --broadcast
contract DeployTestnet is Script {
    // Foundry deterministic CREATE2 deployer used by `new Contract{salt}()`
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address poolManager = vm.envAddress("POOL_MANAGER");
        address securityCouncil = vm.envOr("SECURITY_COUNCIL", deployer);
        address governance = vm.envOr("GOVERNANCE", address(0));

        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        uint256 quoteTokenIndex = vm.envOr("QUOTE_TOKEN_INDEX", uint256(1));
        bool deployCredentialFlag = vm.envOr("DEPLOY_CREDENTIAL", true);

        console.log("========================================");
        console.log("  Fixer v2.3 Testnet Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("PoolManager:", poolManager);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy or resolve tokens
        (address token0Addr, address token1Addr) = _resolveTokens(deployer);

        // Deploy registry
        address proxy = _deployRegistry(deployer, securityCouncil, governance);

        // Deploy hook
        address hook = _deployHook(
            CREATE2_DEPLOYER, poolManager, proxy, token0Addr, token1Addr,
            fee, tickSpacing, quoteTokenIndex
        );

        // Register hook
        _registerHook(proxy, hook);

        // Deploy credential
        address credentialAddr;
        if (deployCredentialFlag) {
            credentialAddr = _deployCredential(proxy, deployer);
        }

        vm.stopBroadcast();

        // Summary
        _logSummary(proxy, hook, credentialAddr, token0Addr, token1Addr);
    }

    function _resolveTokens(
        address deployer
    ) internal returns (address token0Addr, address token1Addr) {
        token0Addr = vm.envOr("TOKEN0", address(0));
        token1Addr = vm.envOr("TOKEN1", address(0));

        if (token0Addr == address(0) || token1Addr == address(0)) {
            console.log("");
            console.log("--- Deploying Mock Tokens ---");

            MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);
            MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);

            mockWETH.mint(deployer, 100 ether);
            mockUSDC.mint(deployer, 100_000e6);

            if (address(mockWETH) < address(mockUSDC)) {
                token0Addr = address(mockWETH);
                token1Addr = address(mockUSDC);
            } else {
                token0Addr = address(mockUSDC);
                token1Addr = address(mockWETH);
            }

            console.log("Mock WETH:", address(mockWETH));
            console.log("Mock USDC:", address(mockUSDC));
            console.log("Token0 (sorted):", token0Addr);
            console.log("Token1 (sorted):", token1Addr);
        } else {
            require(token0Addr < token1Addr, "TOKEN0 must be < TOKEN1 by address");
        }
    }

    function _deployRegistry(
        address deployer,
        address securityCouncil,
        address governance
    ) internal returns (address) {
        console.log("");
        console.log("--- Deploying Registry ---");

        FixerRegistryUpgradeable implementation = new FixerRegistryUpgradeable();
        console.log("Implementation:", address(implementation));

        bytes memory initData = abi.encodeCall(
            FixerRegistryUpgradeable.initialize,
            (deployer, securityCouncil, governance)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy:", address(proxy));

        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(address(proxy)));
        require(registry.owner() == deployer, "Owner mismatch");
        require(registry.VERSION() == 2_003_000, "Version mismatch");

        (uint64 feeBps,) = registry.getProtocolFeeConfig();
        console.log("VERSION:", registry.VERSION());
        console.log("Protocol Fee:", feeBps, "bps");

        return address(proxy);
    }

    function _deployHook(
        address deployer,
        address poolManager,
        address registryProxy,
        address token0Addr,
        address token1Addr,
        uint24 fee,
        int24 tickSpacing,
        uint256 quoteTokenIndex
    ) internal returns (address) {
        console.log("");
        console.log("--- Deploying Hook ---");

        Currency currency0 = Currency.wrap(token0Addr);
        Currency currency1 = Currency.wrap(token1Addr);
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager),
            IFixerRegistry(registryProxy),
            currency0,
            currency1,
            fee,
            tickSpacing,
            quoteTokenIndex
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer, flags, type(FixerHookV2).creationCode, constructorArgs
        );
        console.log("Mined hook address:", hookAddress);

        FixerHookV2 hook = new FixerHookV2{salt: salt}(
            IPoolManager(poolManager),
            IFixerRegistry(registryProxy),
            currency0,
            currency1,
            fee,
            tickSpacing,
            quoteTokenIndex
        );

        require(address(hook) == hookAddress, "Hook address mismatch");
        console.log("FixerHookV2:", address(hook));
        return address(hook);
    }

    function _registerHook(address registryProxy, address hook) internal {
        FixerRegistryUpgradeable registry = FixerRegistryUpgradeable(payable(registryProxy));
        bytes32 storedPoolId = FixerHookV2(hook).getPoolId();
        registry.registerHook(address(hook), storedPoolId);
        console.log("Hook registered for pool:", vm.toString(storedPoolId));
    }

    function _deployCredential(
        address registryProxy,
        address owner
    ) internal returns (address) {
        console.log("");
        console.log("--- Deploying Credential ---");

        FixerCredential credential = new FixerCredential(
            IFixerRegistry(registryProxy), owner
        );
        console.log("FixerCredential:", address(credential));
        return address(credential);
    }

    function _logSummary(
        address proxy,
        address hook,
        address credentialAddr,
        address token0Addr,
        address token1Addr
    ) internal view {
        bytes32 poolId = FixerHookV2(hook).getPoolId();

        console.log("");
        console.log("========================================");
        console.log("  Deployment Summary");
        console.log("========================================");
        console.log("Registry Proxy:", proxy);
        console.log("FixerHookV2:", hook);
        if (credentialAddr != address(0)) {
            console.log("FixerCredential:", credentialAddr);
        }
        console.log("Pool ID:", vm.toString(poolId));
        console.log("Token0:", token0Addr);
        console.log("Token1:", token1Addr);
        console.log("");
        console.log("Update .env with:");
        console.log("  FIXER_REGISTRY=", proxy);
        console.log("  FIXER_HOOK=", hook);
        console.log("  PROXY_ADDRESS=", proxy);
        if (credentialAddr != address(0)) {
            console.log("  FIXER_CREDENTIAL=", credentialAddr);
        }
    }
}
