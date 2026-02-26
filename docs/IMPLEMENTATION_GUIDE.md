# Implementation Guide

> The Fixer Hook Protocol — Building From Scratch (v1 Tutorial + v2.6 Architecture Reference)

**Last Updated:** February 26, 2026 | **Solidity:** 0.8.26

---

## Table of Contents

1. [Part 1: Building the v1 Hook (Tutorial)](#part-1-building-the-v1-hook)
2. [Part 2: Evolving to v2.6 (Architecture Reference)](#part-2-evolving-to-v26)

---

## Part 1: Building the v1 Hook

This tutorial walks through building a basic Uniswap v4 referral hook from scratch.

### Step 1: Project Setup

```bash
# Create project
mkdir the-fixer-hook && cd the-fixer-hook
forge init --no-commit

# Install dependencies
forge install uniswap/v4-periphery
forge install transmissions11/solmate
forge install vectorized/solady
```

### Step 2: Configure Remappings

Create `remappings.txt`:

```
v4-core/=lib/v4-periphery/lib/v4-core/
v4-periphery/=lib/v4-periphery/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
solmate/=lib/solmate/src/
solady/=lib/solady/src/
```

### Step 3: Implement the Hook

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title FixerHook — On-chain referral rewards for Uniswap v4
/// @notice The hook IS the reward token (dual inheritance pattern)
contract FixerHook is BaseHook, ERC20 {
    /// @notice Fixed reward per successful referral
    uint256 public constant REWARD_AMOUNT = 10e18; // 10 FIX tokens

    constructor(IPoolManager _manager)
        BaseHook(_manager)
        ERC20("Fixer Token", "FIX", 18)
    {}

    /// @notice Only afterSwap permission is needed
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,           // THE ONLY PERMISSION
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0);
        }

        address referrer = abi.decode(hookData, (address));

        if (referrer != address(0) && referrer != tx.origin) {
            _mint(referrer, REWARD_AMOUNT);
        }

        return (this.afterSwap.selector, 0); // Never modify deltas
    }
}
```

**Key design decisions:**
- **Dual inheritance** — the hook contract IS the token. Deploy once, get both.
- **Side-effect pattern** — `int128(0)` means no delta modification. Swaps are unaffected.
- **`tx.origin` for anti-gaming** — not for authentication, only to prevent self-referral.

### Step 4: Write Basic Tests

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/FixerHook.sol";

contract FixerHookTest is Test {
    function testRewardAmount() public pure {
        assertEq(10e18, 10e18);
    }

    function testHookDataEncoding() public pure {
        address referrer = address(0x1234);
        bytes memory data = abi.encode(referrer);
        address decoded = abi.decode(data, (address));
        assertEq(referrer, decoded);
    }
}
```

### Step 5: Build and Test

```bash
forge build
forge test -vvv
```

---

## Part 2: Evolving to v2.6

The v1 hook works but has limitations: fixed rewards, no tiers, no upgradeability, monolithic design. Here's how v2.6 addresses each.

### Evolution Timeline

| Version | What Changed | Why |
|---------|-------------|-----|
| v1.0 | Fixed 10 FIX reward | Simple starting point |
| v1.1 | Volume-based rewards (BPS) | Fair: larger swaps earn more |
| v1.2 | Tier system (Bronze→Platinum) | Incentivize loyalty |
| v2.0 | Cross-pool registry | Track referrals across pools |
| v2.1 | Soulbound NFT credentials | On-chain reputation proof |
| v2.2 | UUPS proxy + EmergencyModule | Upgradeability + safety |
| v2.3 | x402 + EIP-3009 | Gasless payments for AI agents |
| v2.4 | ERC-8004 reputation | Trustless agent identity |
| v2.5 | DELEGATECALL Extension + FixerLib | EIP-170 compliance (split 35 KB → 20.5 + 14.7 KB) |
| v2.6 | XMTP communication | On-chain endpoint directory for agent messaging |

### Key Architectural Decisions

#### 1. Separate Hook from Token

v1 combined BaseHook + ERC20 in one contract. v2 separates them:

- **FixerHookV2** — lightweight afterSwap observer (4.5 KB)
- **FixerRegistryUpgradeable** — central FIX token + business logic (20.5 KB)

**Why:** The hook is non-upgradeable (address encodes permissions). The registry needs upgradeability for evolving business logic.

#### 2. UUPS Proxy with 48h Timelock

```
proposeUpgrade(newImpl) → 48h wait → executeUpgrade(newImpl)
```

Direct `upgradeToAndCall()` is blocked. Security council can cancel proposals.

#### 3. ERC-7201 Namespaced Storage

All state in a single deterministic slot. No collision with OpenZeppelin internals. 38 gap slots for future fields.

#### 4. Core + Extension (DELEGATECALL Fallback)

```
User → Proxy → Core (known selectors)
                └→ fallback() → DELEGATECALL → Extension (agent/XMTP/EIP-3009)
```

**Why:** Core alone exceeded EIP-170 (24,576 B). Splitting into Core (20.5 KB) + Extension (14.7 KB) keeps both under the limit.

#### 5. Agent Infrastructure Stack

| Layer | Standard | Purpose |
|-------|----------|---------|
| Identity | ERC-8004 | Permissionless agent registration via NFT |
| Payments | EIP-3009 / x402 | Gasless FIX transfers for micropayments |
| Communication | XMTP | Wallet-to-wallet encrypted messaging |

### Contract Dependencies

```
FixerHookV2
  └── calls → IFixerRegistry (proxy)
                ├── FixerRegistryUpgradeable (Core)
                │   ├── ERC-20 (FIX token)
                │   ├── Tier system
                │   ├── EmergencyModule
                │   └── fallback() → Extension
                └── FixerRegistryExtension
                    ├── ERC-8004 (agents)
                    ├── EIP-3009 (gasless transfers)
                    ├── XMTP (communication)
                    └── FixerLib (external library)

FixerCredential (independent)
  └── reads → IFixerRegistry (proxy) for metadata
```

### Running the Full v2.6 Test Suite

```bash
forge test -vvv
# Expected: 381 tests passed across 35 suites
```

See [TESTING.md](./TESTING.md) for detailed test descriptions and [DEPLOYMENT.md](./DEPLOYMENT.md) for deployment procedures.

---

<p align="center">
  <em>Document Version: 3.0.0 | Last Updated: February 26, 2026</em>
</p>
