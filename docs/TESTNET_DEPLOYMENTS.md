# Live Testnet Deployments

> Fixer Protocol v2.6 -- Agent Infrastructure Stack (ERC-8004 + x402 + XMTP)

**Deployed:** June 2025 (v2.5.0) | **Upgraded:** February 25, 2026 (v2.6.0 EXECUTED via TimewarpExtension)
**Version:** 2.6.0 (VERSION constant: `2_006_000`) -- **LIVE on all 4 chains**
**Deployer:** `0xDDe9D31a31d6763612C7f535f51E5dC9f830682e`
**Verified on:** [Blockscout](https://blockscout.com) (21/24 verified, 3 ERC1967 proxies = expected) -- Lasna uses [Reactscan](https://lasna.reactscan.net) (no programmatic source verification API)

---

## Agent Infrastructure Stack

v2.6.0 implements the complete **Agent Infrastructure Stack** with three protocol layers:

| Layer | Protocol | Status | Description |
|-------|----------|--------|-------------|
| **Identity & Trust** | ERC-8004 | 100% on-chain | NFT-based agent identity, reputation scoring, credential delegation |
| **Payments** | x402 | Production-ready | EIP-3009 gasless transfers, micropayment-gated RaaS API, USDC on Base |
| **Communication** | XMTP | 100% on-chain | Agent-to-agent encrypted messaging, on-chain endpoint discovery |

---

## Architecture: Reactive Modular (DELEGATECALL Fallback)

Uses a **Core + Extension** architecture to stay under the EIP-170 contract size limit (24,576 bytes):

| Component | Size | Description |
|-----------|------|-------------|
| **FixerLib** | 2,308 B | Shared computation library (CREATE2 deployed) |
| **FixerRegistryUpgradeable** (Core) | 20,507 B | UUPS implementation: referrals, ERC-20 FIX token, tiers, emergency, hooks, admin |
| **FixerRegistryExtension** | 14,659 B | ERC-8004 agents, XMTP communication, delegation, reputation, EIP-3009 gasless transfers |
| **ERC1967Proxy** | 130 B | Transparent proxy users interact with |
| **FixerHookV2** | 4,480 B | Uniswap v4 `afterSwap` hook (CREATE2-mined address) |
| **FixerCredential** | 11,787 B | Soulbound ERC-721 reputation NFT with on-chain SVG |

The Core contract's `fallback()` function routes unknown selectors to the Extension via `DELEGATECALL`. Both share the same ERC-7201 namespaced storage layout.

```
User → ERC1967Proxy → FixerRegistryUpgradeable (Core)
                         ├── Known selectors: handled directly
                         └── Unknown selectors → fallback() → DELEGATECALL → FixerRegistryExtension
```

---

## Deployed Contracts

### Unichain Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `1301` |
| **RPC** | `https://sepolia.unichain.org` |
| **Block Explorer** | [unichain-sepolia.blockscout.com](https://unichain-sepolia.blockscout.com) |
| **PoolManager** | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |

| Contract | Address | Verified |
|----------|---------|----------|
| FixerLib | [`0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3`](https://unichain-sepolia.blockscout.com/address/0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3) | ✓ |
| Registry Implementation | [`0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960`](https://unichain-sepolia.blockscout.com/address/0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960) | ✓ |
| **Registry Proxy** | [`0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9`](https://unichain-sepolia.blockscout.com/address/0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9) | — |
| FixerRegistryExtension | [`0x23f23CA1E68eE959c969A6FFD4E1e7Dfb81F5246`](https://unichain-sepolia.blockscout.com/address/0x23f23CA1E68eE959c969A6FFD4E1e7Dfb81F5246) | ✓ |
| **FixerHookV2** | [`0x8D965484Bedb2CdEC65f919a91005b795c854040`](https://unichain-sepolia.blockscout.com/address/0x8D965484Bedb2CdEC65f919a91005b795c854040) | ✓ |
| **FixerCredential** | [`0x3e0d0028DE34fbFe0365d52d9D5D955E0F193EBb`](https://unichain-sepolia.blockscout.com/address/0x3e0d0028DE34fbFe0365d52d9D5D955E0F193EBb) | ✓ |

**v2.6.0 Upgrade (XMTP Communication) -- EXECUTED Feb 25, 2026:**

| Contract | Address | Verified |
|----------|---------|----------|
| New Registry Impl (v2.6.0) | [`0xC752308cf7c663De032018713F1D2481EC45b3bD`](https://unichain-sepolia.blockscout.com/address/0xC752308cf7c663De032018713F1D2481EC45b3bD) | ✓ |
| New Extension (XMTP) | [`0x2bF8E2e5f71645ad9e56cADb733141b41DD258B0`](https://unichain-sepolia.blockscout.com/address/0x2bF8E2e5f71645ad9e56cADb733141b41DD258B0) | ✓ |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x31d0220469e10c4E71834a79b1f276d740d3768F` (6 decimals) |
| Currency1 (WETH) | `0x4200000000000000000000000000000000000006` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |

---

### Base Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `84532` |
| **RPC** | `https://sepolia.base.org` |
| **Block Explorer** | [base-sepolia.blockscout.com](https://base-sepolia.blockscout.com) |
| **PoolManager** | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |

| Contract | Address | Verified |
|----------|---------|----------|
| FixerLib | [`0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3`](https://base-sepolia.blockscout.com/address/0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3) | ✓ |
| Registry Implementation | [`0xef7801E05D1C1737Fb8dD96de4FF8AB09efDACE6`](https://base-sepolia.blockscout.com/address/0xef7801E05D1C1737Fb8dD96de4FF8AB09efDACE6) | ✓ |
| **Registry Proxy** | [`0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960`](https://base-sepolia.blockscout.com/address/0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960) | — |
| FixerRegistryExtension | [`0xC7206C83702B251A5408B28Ce4df195255F42B9e`](https://base-sepolia.blockscout.com/address/0xC7206C83702B251A5408B28Ce4df195255F42B9e) | ✓ |
| **FixerHookV2** | [`0x2CE392Ba90fcAeE3CD23dBcFe11fC2Dc098A8040`](https://base-sepolia.blockscout.com/address/0x2CE392Ba90fcAeE3CD23dBcFe11fC2Dc098A8040) | ✓ |
| **FixerCredential** | [`0xB624bbeC6e044365d365A7f66A253abf27226f82`](https://base-sepolia.blockscout.com/address/0xB624bbeC6e044365d365A7f66A253abf27226f82) | ✓ |

**v2.6.0 Upgrade (XMTP Communication) -- EXECUTED Feb 25, 2026:**

| Contract | Address | Verified |
|----------|---------|----------|
| New Registry Impl (v2.6.0) | [`0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb`](https://base-sepolia.blockscout.com/address/0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb) | ✓ |
| New Extension (XMTP) | [`0xC752308cf7c663De032018713F1D2481EC45b3bD`](https://base-sepolia.blockscout.com/address/0xC752308cf7c663De032018713F1D2481EC45b3bD) | ✓ |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (6 decimals) |
| Currency1 (WETH) | `0x4200000000000000000000000000000000000006` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |

---

### Arbitrum Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `421614` |
| **RPC** | `https://sepolia-rollup.arbitrum.io/rpc` |
| **Block Explorer** | [arbitrum-sepolia.blockscout.com](https://arbitrum-sepolia.blockscout.com) |
| **PoolManager** | `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` |

| Contract | Address | Verified |
|----------|---------|----------|
| FixerLib | [`0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3`](https://arbitrum-sepolia.blockscout.com/address/0x2A29cc3CAE2Cd0198789497CEE4178Af26AEB9e3) | ✓ |
| Registry Implementation | [`0x3e0d0028DE34fbFe0365d52d9D5D955E0F193EBb`](https://arbitrum-sepolia.blockscout.com/address/0x3e0d0028DE34fbFe0365d52d9D5D955E0F193EBb) | ✓ |
| **Registry Proxy** | [`0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb`](https://arbitrum-sepolia.blockscout.com/address/0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb) | — |
| FixerRegistryExtension | [`0x2bF8E2e5f71645ad9e56cADb733141b41DD258B0`](https://arbitrum-sepolia.blockscout.com/address/0x2bF8E2e5f71645ad9e56cADb733141b41DD258B0) | ✓ |
| **FixerHookV2** | [`0x1bf835D48d3a7743dc4A179B0bE2b9dD9a8cC040`](https://arbitrum-sepolia.blockscout.com/address/0x1bf835D48d3a7743dc4A179B0bE2b9dD9a8cC040) | ✓ |
| **FixerCredential** | [`0x72489A460c90210e0Cfb0d24B2646F10D38EAcc1`](https://arbitrum-sepolia.blockscout.com/address/0x72489A460c90210e0Cfb0d24B2646F10D38EAcc1) | ✓ |

**v2.6.0 Upgrade (XMTP Communication) -- EXECUTED Feb 25, 2026:**

| Contract | Address | Verified |
|----------|---------|----------|
| New Registry Impl (v2.6.0) | [`0x6c1Bb082B63a97c52Fc9868A388b2FcE93862F52`](https://arbitrum-sepolia.blockscout.com/address/0x6c1Bb082B63a97c52Fc9868A388b2FcE93862F52) | ✓ |
| New Extension (XMTP) | [`0xAb340F430A1346923B4e0722B67bbCc500A6F6Db`](https://arbitrum-sepolia.blockscout.com/address/0xAb340F430A1346923B4e0722B67bbCc500A6F6Db) | ✓ |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` (6 decimals) |
| Currency1 (WETH) | `0xE591bf0A0CF924A0674d7792db046B23CEbF5f34` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |

---

### Lasna (Reactive Network)

| Property | Value |
|----------|-------|
| **Chain ID** | `5318007` |
| **RPC** | `https://lasna-rpc.rnk.dev/` |
| **Block Explorer** | [lasna.reactscan.net](https://lasna.reactscan.net) |
| **Currency** | lREACT |
| **PoolManager** | _None — Reactive Network has no Uniswap v4_ |

> **Note:** Lasna is the Reactive Network's execution layer for cross-chain event automation. There is no Uniswap v4 PoolManager on this chain, so **FixerHookV2 is not deployed**. Only the Registry, Extension, and Credential contracts are deployed here to support Reactive Contract integrations (e.g., cross-chain referral sync).

| Contract | Address | Verified |
|----------|---------|----------|
| FixerLib | [`0xfD870250416F3127b8111fDE1D8dEBDc31D1BCA2`](https://lasna.reactscan.net/address/0xfD870250416F3127b8111fDE1D8dEBDc31D1BCA2) | — |
| Registry Implementation | [`0x8160B7dba69D0B8b144f25a3022acB99509c79b7`](https://lasna.reactscan.net/address/0x8160B7dba69D0B8b144f25a3022acB99509c79b7) | — |
| **Registry Proxy** | [`0xd2f11a95F1ca8cc94FB63926dc3A92655aAc6fF3`](https://lasna.reactscan.net/address/0xd2f11a95F1ca8cc94FB63926dc3A92655aAc6fF3) | — |
| FixerRegistryExtension | [`0x2e0379c6226Ae9e2327cF86ABCbC26f68fbE290D`](https://lasna.reactscan.net/address/0x2e0379c6226Ae9e2327cF86ABCbC26f68fbE290D) | — |
| **FixerCredential** | [`0xB9356961aa61AA1148f39Dd0C748656C3E574596`](https://lasna.reactscan.net/address/0xB9356961aa61AA1148f39Dd0C748656C3E574596) | — |

**v2.6.0 Upgrade (XMTP Communication) -- EXECUTED Feb 25, 2026:**

| Contract | Address | Verified |
|----------|---------|----------|
| New Registry Impl (v2.6.0) | [`0x6Cc135698BFE7B109E581f73A814E3aF4e919908`](https://lasna.reactscan.net/address/0x6Cc135698BFE7B109E581f73A814E3aF4e919908) | — |
| New Extension (XMTP) | [`0x6d192eB2E06A3C48832047D5ccA775c60E87034C`](https://lasna.reactscan.net/address/0x6d192eB2E06A3C48832047D5ccA775c60E87034C) | — |

> Source verification not available — Reactscan does not support programmatic contract verification (API returns 404). Contracts are deployed and functional but cannot be source-verified.

---

## On-Chain Verification

```bash
# Replace <PROXY> and <HOOK> with addresses from the tables above

# Registry version (expect: 2006000 — v2.6.0 upgrade executed on all chains)
cast call <PROXY> "VERSION()(uint256)" --rpc-url <RPC>

# Registry owner (expect: 0xDDe9D31a...682e)
cast call <PROXY> "owner()(address)" --rpc-url <RPC>

# FIX token metadata
cast call <PROXY> "name()(string)" --rpc-url <RPC>    # "Fixer Token"
cast call <PROXY> "symbol()(string)" --rpc-url <RPC>   # "FIX"

# Hook authorization (expect: true)
cast call <PROXY> "isAuthorizedHook(address)(bool)" <HOOK> --rpc-url <RPC>

# Extension address
cast call <PROXY> "getExtension()(address)" --rpc-url <RPC>

# Pool ID stored in hook
cast call <HOOK> "getPoolId()(bytes32)" --rpc-url <RPC>

# XMTP enabled count (v2.6.0+ only)
cast call <PROXY> "getXMTPEnabledCount()(uint64)" --rpc-url <RPC>

# Check pending upgrade proposal
cast call <PROXY> "getPendingUpgrade()(address,uint256,bool,uint256)" --rpc-url <RPC>
```

---

## How to Interact

### Faucets

| Network | Faucet |
|---------|--------|
| Base Sepolia | [faucet.quicknode.com/base/sepolia](https://faucet.quicknode.com/base/sepolia) |
| Arbitrum Sepolia | [faucet.quicknode.com/arbitrum/sepolia](https://faucet.quicknode.com/arbitrum/sepolia) |
| Unichain Sepolia | Bridge from Ethereum Sepolia via OptimismPortal `0x0d83dab629f0e0F9d36c0Cbc89B69a489f0751bD` |
| Lasna (Reactive) | Send Sepolia ETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` (1:100 ratio, max 5 ETH/tx) |

### Swaps with Referrals

```solidity
bytes memory hookData = abi.encode(referrerAddress);
// Pass hookData to Uniswap v4 swap router
```

```bash
# Encode referrer address for hookData
cast abi-encode "f(address)" 0x1234...abcd
```

### Credential NFT

```bash
cast send <CREDENTIAL> "mint(address)(uint256)" <REFERRER> --private-key <KEY> --rpc-url <RPC>
cast call <CREDENTIAL> "tokenURI(uint256)(string)" <TOKEN_ID> --rpc-url <RPC>
```

---

## Deployment Scripts

### Fresh Deployment

| Script | Network | Command |
|--------|---------|---------|
| `DeployBaseSepolia.s.sol` | Base Sepolia | `forge script script/DeployBaseSepolia.s.sol --rpc-url base_sepolia --broadcast -vvvv` |
| `DeployArbSepolia.s.sol` | Arbitrum Sepolia | `forge script script/DeployArbSepolia.s.sol --rpc-url arb_sepolia --broadcast -vvvv` |
| `DeployUnichainSepolia.s.sol` | Unichain Sepolia | `forge script script/DeployUnichainSepolia.s.sol --rpc-url unichain_sepolia --broadcast -vvvv` |
| `DeployLasna.s.sol` | Lasna (Reactive) | `forge script script/DeployLasna.s.sol --rpc-url lasna --broadcast -vvvv` |

### v2.6.0 Upgrade (2-Phase Timelock)

The UUPS upgrade uses a 48-hour timelock for security:

```bash
# Phase 1: Deploy new contracts + propose upgrade
PROXY_ADDRESS=0x... forge script script/UpgradeV260Propose.s.sol \
  --rpc-url <chain> --broadcast -vvvv

# Phase 2: Execute after 48h timelock expires
PROXY_ADDRESS=0x... NEW_EXTENSION=0x... forge script script/UpgradeV260Execute.s.sol \
  --rpc-url <chain> --broadcast -vvvv
```

| Chain | Proxy | New Extension |
|-------|-------|---------------|
| Unichain Sepolia | `0xa5589E...d9` | `0x2bF8E2...B0` |
| Base Sepolia | `0x3Fb805...60` | `0xC75230...bD` |
| Arb Sepolia | `0x07dF8c...Eb` | `0xAb340F...Db` |
| Lasna | `0xd2f11a...F3` | `0x6d192e...4C` |

### Verification

```bash
# Free verification via Blockscout (no API key needed)
python3 scripts/verify_blockscout.py base-sepolia
python3 scripts/verify_blockscout.py arb-sepolia

# Unichain uses forge CLI:
forge verify-contract --rpc-url unichain_sepolia <ADDR> <PATH> \
  --verifier blockscout --verifier-url "https://unichain-sepolia.blockscout.com/api/"
```

---

## Deployment Records

- [`deployments/unichain-sepolia-v2.json`](../deployments/unichain-sepolia-v2.json)
- [`deployments/base-sepolia-v2.json`](../deployments/base-sepolia-v2.json)
- [`deployments/arb-sepolia-v2.json`](../deployments/arb-sepolia-v2.json)
- [`deployments/lasna-v2.json`](../deployments/lasna-v2.json)
