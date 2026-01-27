# Implementation Guide

> Step-by-step guide to building the Referral Hook

---

## Prerequisites

- **Foundry** (latest)
- **Solidity 0.8.26**
- Basic understanding of Uniswap v4 hooks

---

## Project Setup

### Step 1: Initialize Foundry Project

```bash
# Create project directory
mkdir the-referral-hook && cd the-referral-hook

# Initialize Foundry
forge init

# Remove boilerplate
rm -rf src/Counter.sol test/Counter.t.sol script/Counter.s.sol
```

### Step 2: Install Dependencies

```bash
# Install Uniswap v4-core
forge install uniswap/v4-core --no-commit

# Install Uniswap v4-periphery
forge install uniswap/v4-periphery --no-commit

# Install Solmate (for ERC20)
forge install transmissions11/solmate --no-commit
```

### Step 3: Configure Remappings

Create `remappings.txt`:

```txt
v4-core/=lib/v4-core/src/
v4-periphery/=lib/v4-periphery/
solmate/=lib/solmate/
forge-std/=lib/forge-std/src/
```

### Step 4: Verify Setup

```bash
forge build
```

---

## Contract Implementation

Create `src/ReferralHook.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract ReferralHook is BaseHook, ERC20 {
    uint256 public constant REWARD_AMOUNT = 10 * 1e18;

    constructor(IPoolManager _manager) 
        BaseHook(_manager) 
        ERC20("Referral Token", "REF", 18) 
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,  // Only this enabled
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (hookData.length > 0) {
            address referrer = abi.decode(hookData, (address));
            if (referrer != address(0) && referrer != tx.origin) {
                _mint(referrer, REWARD_AMOUNT);
            }
        }
        return (BaseHook.afterSwap.selector, 0);
    }
}
```

---

## Code Walkthrough

### Imports Explained

```solidity
// Core Uniswap v4 types and interfaces
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
// Interface for interacting with the PoolManager

import {PoolKey} from "v4-core/types/PoolKey.sol";
// Struct identifying a unique pool (tokens, fee, tickSpacing, hooks)

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
// Packed type representing amount0 and amount1 changes

import {Hooks} from "v4-core/libraries/Hooks.sol";
// Library with Permissions struct and flag constants

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
// Abstract contract implementing IHooks interface

import {ERC20} from "solmate/src/tokens/ERC20.sol";
// ~30% more gas efficient than OpenZeppelin
```

### Inheritance Pattern

```solidity
contract ReferralHook is BaseHook, ERC20 {
```

| Parent | Purpose |
|--------|---------|
| `BaseHook` | Provides Uniswap hook interface, permission handling, selector validation |
| `ERC20` | Allows the hook contract itself to be the reward token (simplicity) |

### Constructor Pattern

```solidity
constructor(IPoolManager _manager) 
    BaseHook(_manager) 
    ERC20("Referral Token", "REF", 18) 
{}
```

1. `BaseHook(_manager)` — Stores PoolManager reference, validates hook address
2. `ERC20("...", "...", 18)` — Initializes token name, symbol, decimals

---

## Testing

Create `test/ReferralHook.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ReferralHook} from "../src/ReferralHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract ReferralHookTest is Test {
    function test_HookPermissions() public {
        // Test permissions are correctly set
    }
    
    function test_ValidReferral() public {
        // Test valid referral mints tokens
    }
    
    function test_SelfReferralBlocked() public {
        // Test self-referral is rejected
    }
}
```

Run tests:

```bash
forge test -vvv
```

---

## Build Verification

```bash
# Build
forge build

# Run tests
forge test

# Gas report
forge test --gas-report

# Coverage
forge coverage
```

---

## Checklist

Use this checklist before moving to deployment:

- [ ] Contract compiles without warnings
- [ ] All tests pass
- [ ] Gas report reviewed
- [ ] Hook permissions verified (only `afterSwap: true`)
- [ ] Token metadata correct (name, symbol, decimals)
- [ ] REWARD_AMOUNT set correctly
- [ ] Code commented and documented

---

## Next Steps

- [Integration Guide](./INTEGRATION_GUIDE.md) — Frontend integration
- [Security Analysis](./SECURITY.md) — Threat model
- [Deployment Guide](./DEPLOYMENT.md) — Production deployment
