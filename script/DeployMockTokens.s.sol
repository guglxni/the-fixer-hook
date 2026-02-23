// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @title DeployMockTokens
/// @notice Deploys mock WETH and USDC for testnet usage
/// @dev Mints 1M of each to deployer; logs sorted TOKEN0/TOKEN1 for Uniswap v4
///
/// Usage:
///   forge script script/DeployMockTokens.s.sol --rpc-url base_sepolia --broadcast -vvvv
contract DeployMockTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Mock Token Deployment ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);

        mockWETH.mint(deployer, 1_000_000e18);
        mockUSDC.mint(deployer, 1_000_000e6);

        vm.stopBroadcast();

        // Uniswap v4 requires currency0 < currency1 by address
        address token0;
        address token1;
        string memory token0Name;
        string memory token1Name;

        if (address(mockWETH) < address(mockUSDC)) {
            token0 = address(mockWETH);
            token1 = address(mockUSDC);
            token0Name = "mWETH";
            token1Name = "mUSDC";
        } else {
            token0 = address(mockUSDC);
            token1 = address(mockWETH);
            token0Name = "mUSDC";
            token1Name = "mWETH";
        }

        console.log("");
        console.log("=== Deployed Tokens ===");
        console.log("Mock WETH:", address(mockWETH));
        console.log("Mock USDC:", address(mockUSDC));
        console.log("");
        console.log("=== Uniswap v4 Ordering ===");
        console.log("TOKEN0 (lower):", token0, token0Name);
        console.log("TOKEN1 (higher):", token1, token1Name);
        console.log("");
        console.log("Set in your environment:");
        console.log("  export TOKEN0=", token0);
        console.log("  export TOKEN1=", token1);
    }
}
