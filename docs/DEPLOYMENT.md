# Deployment Guide

> The Fixer Hook Protocol — Deployment Procedures (v2.6.0)

**Last Updated:** February 26, 2026 | **Version:** 2.6.0

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Network Configuration](#network-configuration)
4. [What Gets Deployed](#what-gets-deployed)
5. [Deployment Process](#deployment-process)
6. [Chain-Specific Scripts](#chain-specific-scripts)
7. [Post-Deployment Verification](#post-deployment-verification)
8. [Upgrade Process](#upgrade-process)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The Fixer Protocol deploys **6–7 contracts** per chain (7 on chains with Uniswap v4, 6 on Lasna which has no PoolManager):

| # | Contract | Purpose | Size |
|:-:|----------|---------|:----:|
| 1 | **FixerLib** | External computation library | 2.3 KB |
| 2 | **FixerRegistryUpgradeable** (implementation) | Core logic: FIX token, referrals, tiers, emergency | 20.5 KB |
| 3 | **ERC1967Proxy** | Transparent proxy users interact with | 130 B |
| 4 | **FixerRegistryExtension** | Agent module: ERC-8004, XMTP, EIP-3009, delegation | 14.7 KB |
| 5 | **FixerCredential** | Soulbound NFT with on-chain SVG | 11.8 KB |
| 6 | **FixerHookV2** | afterSwap hook (CREATE2-mined address) | 4.5 KB |
| — | *Post-deploy calls* | `setExtension()`, `registerHook()`, pool init | — |

On Lasna (Reactive Network), FixerHookV2 (#6) is **not deployed** — there is no Uniswap v4 PoolManager.

---

## Prerequisites

### Tools

```bash
# Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify
forge --version   # >= 0.2.0
cast --version
```

### Environment

```bash
cp .env.example .env
# Fill in:
# PRIVATE_KEY=0x...          (deployer wallet)
# BASE_SEPOLIA_RPC=https://sepolia.base.org
# ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
# UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org
# LASNA_RPC=https://lasna-rpc.rnk.dev/
```

### Deployer Wallet

The deployer becomes the initial `owner` of all contracts. Ensure it has:
- Sufficient native gas tokens on the target chain
- Private key securely stored (not committed to git)

---

## Network Configuration

### Testnets (Live)

| Chain | ID | RPC | PoolManager |
|-------|:--:|-----|-------------|
| Base Sepolia | 84532 | `https://sepolia.base.org` | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| Arbitrum Sepolia | 421614 | `https://sepolia-rollup.arbitrum.io/rpc` | `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` |
| Unichain Sepolia | 1301 | `https://sepolia.unichain.org` | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| Lasna (Reactive) | 5318007 | `https://lasna-rpc.rnk.dev/` | _None_ |

### Mainnet (Planned)

| Chain | ID | PoolManager |
|-------|:--:|-------------|
| Ethereum | 1 | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Base | 8453 | `0x7C5f5A4bBd8fD63184577525326123B519429bDc` |
| Arbitrum One | 42161 | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` |
| Unichain | 130 | TBD |

### foundry.toml RPC Aliases

```toml
[rpc_endpoints]
base_sepolia = "${BASE_SEPOLIA_RPC}"
arb_sepolia = "${ARB_SEPOLIA_RPC}"
unichain_sepolia = "${UNICHAIN_SEPOLIA_RPC}"
lasna = "${LASNA_RPC}"
```

---

## What Gets Deployed

### Full Stack (Base / Arb / Unichain Sepolia)

```
Transaction 1: Deploy FixerLib (CREATE2)
Transaction 2: Deploy FixerRegistryUpgradeable implementation
Transaction 3: Deploy ERC1967Proxy + initialize()
Transaction 4: Deploy FixerRegistryExtension
Transaction 5: Call proxy.setExtension(extension)
Transaction 6: Deploy FixerHookV2 (CREATE2-mined address with correct permission bits)
Transaction 7: Call proxy.registerHook(hookAddress)
Transaction 8: Deploy FixerCredential
Transaction 9: Initialize pool with PoolManager (optional)
```

### Reactive Network (Lasna) — No Hook

```
Transaction 1: Deploy FixerLib (CREATE2)
Transaction 2: Deploy FixerRegistryUpgradeable implementation
Transaction 3: Deploy ERC1967Proxy + initialize()
Transaction 4: Deploy FixerRegistryExtension
Transaction 5: Call proxy.setExtension(extension)
Transaction 6: Deploy FixerCredential
```

No FixerHookV2, no hook registration, no pool initialization.

---

## Deployment Process

### Step 1: Build

```bash
forge build
```

Ensure all contracts compile without errors. Optimizer: enabled, 1 run, via_ir=true, Cancun EVM.

### Step 2: Hook Address Mining

FixerHookV2 requires a CREATE2-mined address where the lowest 14 bits encode the hook permissions. The `HookMiner.sol` script finds a valid salt:

```bash
# This is done automatically in the deployment scripts
# HookMiner.find(deployer, CREATE2_DEPLOYER, creationCode, FLAGS)
```

The mined address must have bit 7 set (afterSwap = true) and all other permission bits clear.

### Step 3: Deploy

```bash
# Base Sepolia
forge script script/DeployBaseSepolia.s.sol \
  --rpc-url base_sepolia --broadcast -vvvv

# Arbitrum Sepolia
forge script script/DeployArbSepolia.s.sol \
  --rpc-url arb_sepolia --broadcast -vvvv

# Unichain Sepolia
forge script script/DeployUnichainSepolia.s.sol \
  --rpc-url unichain_sepolia --broadcast -vvvv

# Lasna (Reactive Network) — no hook
forge script script/DeployLasna.s.sol \
  --rpc-url lasna --broadcast -vvvv
```

### Step 4: Record Addresses

After deployment, save all addresses to `deployments/<chain>-v2.json`:

| Address to Record | Source |
|-------------------|--------|
| FixerLib | CREATE2 deployment |
| Registry Implementation | Contract creation |
| Registry Proxy (ERC1967) | Proxy creation |
| FixerRegistryExtension | Contract creation |
| FixerHookV2 | CREATE2 deployment (skip on Lasna) |
| FixerCredential | Contract creation |

### Step 5: Verify Contracts

```bash
# Free verification via Blockscout (no API key needed)
python3 scripts/verify_blockscout.py base-sepolia
python3 scripts/verify_blockscout.py arb-sepolia

# Unichain uses forge CLI:
forge verify-contract --rpc-url unichain_sepolia <ADDR> <PATH> \
  --verifier blockscout \
  --verifier-url "https://unichain-sepolia.blockscout.com/api/"

# Lasna: Reactscan has no programmatic verification API
```

---

## Chain-Specific Scripts

| Script | Chain | Notes |
|--------|-------|-------|
| `DeployBaseSepolia.s.sol` | Base Sepolia | Full stack + USDC/WETH pool init |
| `DeployArbSepolia.s.sol` | Arbitrum Sepolia | Full stack + USDC/WETH pool init |
| `DeployUnichainSepolia.s.sol` | Unichain Sepolia | Full stack + USDC/WETH pool init |
| `DeployLasna.s.sol` | Lasna (Reactive) | Registry + Extension + Credential only |
| `DeployTestnet.s.sol` | Generic | Env-configured for any chain |
| `DeployUpgradeable.s.sol` | Generic | UUPS proxy deployment |
| `DeployV2.s.sol` | Generic | FixerHookV2 + FixerRegistry |
| `DeployX402.s.sol` | Generic | v2.3 x402 enhancement |

---

## Post-Deployment Verification

```bash
# Replace <PROXY>, <HOOK>, <RPC> with actual values

# VERSION — expect 2006000 (v2.6.0)
cast call <PROXY> "VERSION()(uint256)" --rpc-url <RPC>

# Owner — expect deployer address
cast call <PROXY> "owner()(address)" --rpc-url <RPC>

# FIX token metadata
cast call <PROXY> "name()(string)" --rpc-url <RPC>     # "Fixer Token"
cast call <PROXY> "symbol()(string)" --rpc-url <RPC>    # "FIX"

# Extension address — should not be address(0)
cast call <PROXY> "getExtension()(address)" --rpc-url <RPC>

# Hook authorization — expect true
cast call <PROXY> "isAuthorizedHook(address)(bool)" <HOOK> --rpc-url <RPC>

# XMTP enabled count — expect 0 initially
cast call <PROXY> "getXMTPEnabledCount()(uint64)" --rpc-url <RPC>

# Hook pool ID
cast call <HOOK> "getPoolId()(bytes32)" --rpc-url <RPC>
```

---

## Upgrade Process

### UUPS + 48-Hour Timelock

All upgrades follow a **two-phase process**:

#### Phase 1: Propose + Deploy New Contracts

```bash
PROXY_ADDRESS=0x... forge script script/UpgradeV260Propose.s.sol \
  --rpc-url <chain> --broadcast -vvvv
```

This:
1. Deploys new FixerRegistryUpgradeable implementation
2. Deploys new FixerRegistryExtension (if changed)
3. Calls `proposeUpgrade(newImplementation)` on the proxy
4. Starts the 48-hour timelock

#### Phase 2: Execute (After 48h)

```bash
PROXY_ADDRESS=0x... NEW_EXTENSION=0x... forge script script/UpgradeV260Execute.s.sol \
  --rpc-url <chain> --broadcast -vvvv
```

This:
1. Calls `executeUpgrade(newImplementation)`
2. Internally calls `upgradeToAndCall()` — which validates via `_authorizeUpgrade()`
3. Calls `setExtension(newExtension)` if extension changed
4. Runs reinitializer for new version

#### Emergency: Cancel Upgrade

```bash
cast send <PROXY> "cancelUpgrade()" --private-key <KEY> --rpc-url <RPC>
```

Cancels a pending proposal before the 48h timelock expires.

---

## Troubleshooting

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "Hook address validation failing" | CREATE2 salt produces wrong permission bits | Re-run HookMiner with correct flags |
| "Contract too large" | Exceeds EIP-170 limit (24,576 B) | Ensure `via_ir=true` and optimizer runs=1 in foundry.toml |
| "Already initialized" | Calling initialize() on already-initialized proxy | Use reinitialize() with next version number |
| "Upgrade timelock not expired" | Executing upgrade before 48h | Wait for `block.timestamp >= proposedAt + 172800` |
| Slow compilation | `via_ir` pipeline is slow | Disable for development (`via_ir = false`), enable for deployment |
| "EvmError: OutOfGas" in deployment | Complex constructor or init | Increase gas limit: `--gas-limit 30000000` |
| Blockscout verification failing | Wrong constructor args or compiler settings | Ensure exact match of solc version (0.8.26), optimizer config, via_ir flag |

### Gas Considerations

- **via_ir optimization:** Required for production deployments (reduces contract size ~20%)
- **Optimizer runs: 1** — optimizes for deployment cost over call cost (appropriate for single-deploy contracts)
- **Cancun EVM:** Required for TSTORE/TLOAD in reentrancy guard

---

<p align="center">
  <em>Document Version: 3.0.0 | Last Updated: February 26, 2026</em>
</p>
