# Live Testnet Deployments

> Fixer Protocol v2.3 — Deployed and verified on three L2 testnets

**Deployed:** February 22, 2026
**Version:** 2.3.0 (VERSION constant: `2003000`)
**Deployer:** `0xDDe9D31a31d6763612C7f535f51E5dC9f830682e`

---

## Deployed Contracts

The full Fixer Protocol v2.3 stack is live on three Uniswap v4 testnets. Each deployment includes four contracts and one registration transaction:

1. **FixerRegistryUpgradeable (Implementation)** — UUPS logic contract
2. **ERC1967Proxy** — Transparent proxy users interact with (the "Registry")
3. **FixerHookV2** — Uniswap v4 `afterSwap` hook (CREATE2-mined address)
4. **FixerCredential** — Soulbound ERC-721 reputation NFT

---

## Architecture Overview

![Deployment Pipeline](diagrams/drawio/deployment-pipeline.png)

![UUPS Proxy Architecture](diagrams/drawio/uups-proxy.png)



### Base Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `84532` |
| **RPC** | `https://sepolia.base.org` |
| **Block Explorer** | [sepolia.basescan.org](https://sepolia.basescan.org) |
| **PoolManager** | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |

| Contract | Address |
|----------|---------|
| Registry Implementation | [`0x758C3046eAC928eFADbFEFbf2dDEaee0D7BAF1B8`](https://sepolia.basescan.org/address/0x758C3046eAC928eFADbFEFbf2dDEaee0D7BAF1B8) |
| **Registry Proxy** | [`0x43c75D09d7e53Ee1c768353708EDC3Bab4317F94`](https://sepolia.basescan.org/address/0x43c75D09d7e53Ee1c768353708EDC3Bab4317F94) |
| **FixerHookV2** | [`0xb66603495944EA622F1c8e312b0d50A8A2F30040`](https://sepolia.basescan.org/address/0xb66603495944EA622F1c8e312b0d50A8A2F30040) |
| **FixerCredential** | [`0xd2fD5c0CaAbE15379a81b3d23081914D69FDA3ef`](https://sepolia.basescan.org/address/0xd2fD5c0CaAbE15379a81b3d23081914D69FDA3ef) |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (6 decimals) |
| Currency1 (WETH) | `0x4200000000000000000000000000000000000006` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |
| Pool ID | `0x83e03329531932d692cd2edb4091647ebe409c67de4980e311149cf8cbee6dc2` |

---

### Arbitrum Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `421614` |
| **RPC** | `https://sepolia-rollup.arbitrum.io/rpc` |
| **Block Explorer** | [sepolia.arbiscan.io](https://sepolia.arbiscan.io) |
| **PoolManager** | `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` |

| Contract | Address |
|----------|---------|
| Registry Implementation | [`0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9`](https://sepolia.arbiscan.io/address/0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9) |
| **Registry Proxy** | [`0xC7206C83702B251A5408B28Ce4df195255F42B9e`](https://sepolia.arbiscan.io/address/0xC7206C83702B251A5408B28Ce4df195255F42B9e) |
| **FixerHookV2** | [`0x7A5E4C1b42d66f459c02b36115d184b907dF0040`](https://sepolia.arbiscan.io/address/0x7A5E4C1b42d66f459c02b36115d184b907dF0040) |
| **FixerCredential** | [`0x0F94b615c27DAfe6D875aE863a77Ea50D9c30b79`](https://sepolia.arbiscan.io/address/0x0F94b615c27DAfe6D875aE863a77Ea50D9c30b79) |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` (6 decimals) |
| Currency1 (WETH) | `0xE591bf0A0CF924A0674d7792db046B23CEbF5f34` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |
| Pool ID | `0x9293ef78c37665a3a4eb2dca397184f6f2fe86c0bdcd45416f7dc92c023b196d` |

---

### Unichain Sepolia

| Property | Value |
|----------|-------|
| **Chain ID** | `1301` |
| **RPC** | `https://sepolia.unichain.org` |
| **Block Explorer** | [sepolia.uniscan.xyz](https://sepolia.uniscan.xyz) |
| **PoolManager** | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |

| Contract | Address |
|----------|---------|
| Registry Implementation | [`0x43c75D09d7e53Ee1c768353708EDC3Bab4317F94`](https://sepolia.uniscan.xyz/address/0x43c75D09d7e53Ee1c768353708EDC3Bab4317F94) |
| **Registry Proxy** | [`0xC13080390D3A1aCCdC7E6bbd7A41981db4bcd56f`](https://sepolia.uniscan.xyz/address/0xC13080390D3A1aCCdC7E6bbd7A41981db4bcd56f) |
| **FixerHookV2** | [`0x983eA96dd196f3F8395A051453505A7c9321c040`](https://sepolia.uniscan.xyz/address/0x983eA96dd196f3F8395A051453505A7c9321c040) |
| **FixerCredential** | [`0x88a31bFDa9B3E24a6bDFE7Ae627CB2C7A134f5c0`](https://sepolia.uniscan.xyz/address/0x88a31bFDa9B3E24a6bDFE7Ae627CB2C7A134f5c0) |

**Pool Configuration:**

| Parameter | Value |
|-----------|-------|
| Currency0 (USDC) | `0x31d0220469e10c4E71834a79b1f276d740d3768F` (6 decimals) |
| Currency1 (WETH) | `0x4200000000000000000000000000000000000006` (18 decimals) |
| Fee | 3000 (0.3%) |
| Tick Spacing | 60 |
| Quote Token Index | 0 (USDC) |
| Pool ID | `0x4defd10c81cdc84f7f9e8c5a4c254d255ef52b72806d752b088896882e0aa2d4` |

---

## On-Chain Verification

All deployments were verified with the following `cast call` checks (all passed):

```bash
# Replace <PROXY> and <HOOK> with addresses from the tables above
# Replace <RPC> with the chain's RPC URL

# Registry version (expect: 2003000)
cast call <PROXY> "VERSION()(uint256)" --rpc-url <RPC>

# Registry owner (expect: 0xDDe9D31a...682e)
cast call <PROXY> "owner()(address)" --rpc-url <RPC>

# FIX token metadata
cast call <PROXY> "name()(string)" --rpc-url <RPC>    # "Fixer Token"
cast call <PROXY> "symbol()(string)" --rpc-url <RPC>   # "FIX"

# Hook authorization (expect: true)
cast call <PROXY> "isAuthorizedHook(address)(bool)" <HOOK> --rpc-url <RPC>

# Pool ID stored in hook
cast call <HOOK> "getPoolId()(bytes32)" --rpc-url <RPC>

# Hook references correct registry
cast call <HOOK> "registry()(address)" --rpc-url <RPC>
```

---

## How to Interact with the Deployed Contracts

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed (`cast`, `forge`)
- Testnet ETH on the target chain (use faucets below)

### Faucets

| Network | Faucet |
|---------|--------|
| Base Sepolia | [faucet.quicknode.com/base/sepolia](https://faucet.quicknode.com/base/sepolia) |
| Arbitrum Sepolia | [faucet.quicknode.com/arbitrum/sepolia](https://faucet.quicknode.com/arbitrum/sepolia) |
| Unichain Sepolia | Bridge from Ethereum Sepolia via OptimismPortal `0x0d83dab629f0e0F9d36c0Cbc89B69a489f0751bD` |

---

### 1. Reading Contract State (No Gas Required)

These are read-only calls — no transaction or private key needed.

#### Check the Registry Version

```bash
cast call 0x43c75D09d7e53Ee1c768353708EDC3Bab4317F94 \
  "VERSION()(uint256)" \
  --rpc-url https://sepolia.base.org
# Output: 2003000
```

#### Query a Referrer's Stats

```bash
cast call <PROXY> \
  "getReferrerStats(address)((uint128,uint64,uint64,uint128,uint8))" \
  <REFERRER_ADDRESS> \
  --rpc-url <RPC>
# Returns: (totalVolume, referralCount, lastUpdated, totalEarned, tier)
# Tier: 0=Bronze, 1=Silver, 2=Gold, 3=Platinum
```

#### Check Tier Progress

```bash
cast call <PROXY> \
  "getProgressToNextTier(address)(uint8,uint8,uint256,uint256)" \
  <REFERRER_ADDRESS> \
  --rpc-url <RPC>
# Returns: (currentTier, nextTier, volumeProgressBps, referralProgressBps)
# Progress values are 0-10000 (basis points, 100% = 10000)
```

#### View Pool Info

```bash
cast call <PROXY> \
  "getPoolInfo(bytes32)((address,bool,uint64,uint128))" \
  <POOL_ID> \
  --rpc-url <RPC>
# Returns: (hookAddress, active, totalReferrals, totalVolume)
```

#### Check Global Protocol Stats

```bash
cast call <PROXY> \
  "getGlobalStats()(uint256,uint256,uint256)" \
  --rpc-url <RPC>
# Returns: (hookCount, totalReferrals, totalVolume)
```

#### Check FIX Token Balance

```bash
cast call <PROXY> \
  "balanceOf(address)(uint256)" \
  <ADDRESS> \
  --rpc-url <RPC>
```

#### View Tier Requirements

```bash
# Check Gold tier thresholds
cast call <PROXY> \
  "getTierThresholds(uint8)((uint128,uint64,uint64))" \
  2 \
  --rpc-url <RPC>
# Returns: (minVolume, minReferrals, multiplierBps)
# Tier enum: 0=Bronze, 1=Silver, 2=Gold, 3=Platinum
```

#### Calculate Estimated Reward

```bash
# Calculate base reward for a swap volume
cast call <PROXY> \
  "calculateReward(uint256)(uint256)" \
  1000000000000000000 \
  --rpc-url <RPC>

# Calculate reward with tier multiplier
cast call <PROXY> \
  "calculateRewardWithTier(uint256,address)(uint256)" \
  1000000000000000000 \
  <REFERRER_ADDRESS> \
  --rpc-url <RPC>
```

---

### 2. Executing Swaps with Referrals

The Fixer Hook processes referrals automatically during Uniswap v4 swaps. To include a referrer, encode their address into the `hookData` parameter of the swap.

#### How the Referral Flow Works

```
1. User calls Uniswap v4 router.swap() with hookData = abi.encode(referrerAddress)
2. PoolManager executes the swap
3. PoolManager calls FixerHookV2.afterSwap() with the hookData
4. FixerHookV2 decodes the referrer address
5. FixerHookV2 resolves the actual swapper (IMsgSender or tx.origin)
6. FixerHookV2 calculates volume from the quote token amount
7. FixerHookV2 calls registry.recordReferral()
8. Registry mints FIX tokens to the referrer (with tier multiplier)
9. If the referrer crosses a tier threshold, a TierUpgrade event is emitted
```

#### Encoding hookData

The hook expects `hookData` to be an ABI-encoded address:

```solidity
// Solidity
bytes memory hookData = abi.encode(referrerAddress);
```

```typescript
// TypeScript (viem)
import { encodeAbiParameters, parseAbiParameters } from 'viem';

const hookData = encodeAbiParameters(
  parseAbiParameters('address'),
  ['0x1234...abcd']  // referrer address
);
```

```typescript
// TypeScript (ethers.js v6)
import { AbiCoder } from 'ethers';

const coder = AbiCoder.defaultAbiCoder();
const hookData = coder.encode(['address'], ['0x1234...abcd']);
```

```bash
# Shell (cast)
cast abi-encode "f(address)" 0x1234...abcd
```

#### Validation Rules

The hook enforces several rules before processing a referral:

| Rule | Effect if Violated |
|------|-------------------|
| `hookData` is empty | Swap proceeds normally, no referral recorded |
| Referrer is `address(0)` | No referral recorded |
| Referrer == Swapper | No referral recorded (self-referral prevention) |
| Volume below `minSwapAmount` | No referral recorded |
| Hook is not authorized in registry | No referral recorded (graceful failure) |

---

### 3. Minting a Credential NFT

After making at least one successful referral, a referrer can mint a soulbound credential NFT.

```bash
# Mint a credential for a referrer (requires at least 1 referral)
cast send <CREDENTIAL> \
  "mint(address)(uint256)" \
  <REFERRER_ADDRESS> \
  --private-key <KEY> \
  --rpc-url <RPC>
```

```bash
# View the credential data
cast call <CREDENTIAL> \
  "getCredential(uint256)((uint8,uint128,uint64,uint64,uint64,bool))" \
  <TOKEN_ID> \
  --rpc-url <RPC>
# Returns: (tier, totalVolume, referralCount, issuedAt, lastUpdated, locked)
```

```bash
# Refresh credential with latest stats from registry
cast send <CREDENTIAL> \
  "refresh(uint256)" \
  <TOKEN_ID> \
  --private-key <KEY> \
  --rpc-url <RPC>
```

```bash
# View on-chain SVG artwork (returns base64 JSON with SVG)
cast call <CREDENTIAL> \
  "tokenURI(uint256)(string)" \
  <TOKEN_ID> \
  --rpc-url <RPC>
```

The credential is soulbound (non-transferable) by default. It displays the referrer's tier with color-coded artwork: Bronze, Silver, Gold, or Platinum.

---

### 4. FIX Token Operations

The FIX token (ERC-20) is minted by the registry when referrals are recorded. It lives at the **Registry Proxy** address (the proxy IS the token contract).

```bash
# Check balance
cast call <PROXY> "balanceOf(address)(uint256)" <ADDRESS> --rpc-url <RPC>

# Total supply
cast call <PROXY> "totalSupply()(uint256)" --rpc-url <RPC>

# Transfer FIX tokens
cast send <PROXY> \
  "transfer(address,uint256)(bool)" \
  <TO_ADDRESS> \
  <AMOUNT> \
  --private-key <KEY> \
  --rpc-url <RPC>

# Approve spending
cast send <PROXY> \
  "approve(address,uint256)(bool)" \
  <SPENDER> \
  <AMOUNT> \
  --private-key <KEY> \
  --rpc-url <RPC>
```

#### Gasless Transfer (EIP-3009)

The FIX token supports gasless transfers via EIP-3009. A payer signs an authorization off-chain, and a facilitator submits the transaction:

```bash
# Check if an authorization nonce has been used
cast call <PROXY> \
  "authorizationState(address,bytes32)(bool)" \
  <AUTHORIZER> \
  <NONCE> \
  --rpc-url <RPC>

# Submit a signed authorization (facilitator pays gas)
cast send <PROXY> \
  "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)" \
  <FROM> <TO> <VALUE> <VALID_AFTER> <VALID_BEFORE> <NONCE> <V> <R> <S> \
  --private-key <FACILITATOR_KEY> \
  --rpc-url <RPC>
```

---

### 5. Monitoring Events

Use `cast logs` or an indexer to watch for protocol activity:

```bash
# Watch for referral events from the registry
cast logs \
  --from-block latest \
  "CrossPoolReferral(address indexed,address indexed,bytes32 indexed,uint256,uint256)" \
  --address <PROXY> \
  --rpc-url <RPC>

# Watch for tier upgrades
cast logs \
  --from-block latest \
  "TierUpgrade(address indexed,uint8 indexed,uint8 indexed)" \
  --address <PROXY> \
  --rpc-url <RPC>

# Watch for credential mints
cast logs \
  --from-block latest \
  "CredentialMinted(address indexed,uint256 indexed,uint8)" \
  --address <CREDENTIAL> \
  --rpc-url <RPC>
```

#### Key Events Reference

| Event | Contract | When Emitted |
|-------|----------|-------------|
| `CrossPoolReferral(referrer, swapper, poolId, volume, reward)` | Registry | Every successful referral |
| `TierUpgrade(referrer, fromTier, toTier)` | Registry | When referrer reaches new tier threshold |
| `HookRegistered(hook, poolId)` | Registry | When a new hook is authorized |
| `ProtocolFeeCollected(fee)` | Registry | When protocol fee is deducted from reward |
| `CredentialMinted(referrer, tokenId, tier)` | Credential | When soulbound NFT is minted |
| `CredentialRefreshed(tokenId, tier)` | Credential | When credential stats are updated |
| `ReferralProcessed(referrer, swapper, poolId, volume, reward)` | Hook | Hook-level confirmation of referral |

---

### 6. Frontend Integration

#### Referral URL Scheme

```typescript
// Generate a referral link
const referralUrl = `https://yourapp.com/swap?ref=${referrerAddress}`;

// Extract referrer from URL
const params = new URLSearchParams(window.location.search);
const referrer = params.get('ref');
```

#### React/Wagmi Integration

```typescript
import { useReadContract } from 'wagmi';

// Read referrer stats
const { data: stats } = useReadContract({
  address: REGISTRY_PROXY,
  abi: registryAbi,
  functionName: 'getReferrerStats',
  args: [referrerAddress],
});

// Read tier progress
const { data: progress } = useReadContract({
  address: REGISTRY_PROXY,
  abi: registryAbi,
  functionName: 'getProgressToNextTier',
  args: [referrerAddress],
});
```

#### Encoding Referral in Swap Transaction

```typescript
import { encodeAbiParameters, parseAbiParameters } from 'viem';

// When building the swap transaction, include hookData
const hookData = referrer
  ? encodeAbiParameters(parseAbiParameters('address'), [referrer])
  : '0x';  // No referrer = normal swap

// Pass hookData to the Uniswap v4 swap router
```

---

## Tier System

Referrers progress through tiers based on cumulative performance:

| Tier | Reward Multiplier | Min Volume | Min Referrals |
|------|-------------------|------------|---------------|
| Bronze | 1.0x (10000 bps) | 0 | 0 |
| Silver | 1.25x (12500 bps) | 10,000 | 10 |
| Gold | 1.5x (15000 bps) | 100,000 | 50 |
| Platinum | 2.0x (20000 bps) | 1,000,000 | 200 |

Tier upgrades happen automatically when `recordReferral()` detects that both thresholds are met.

---

## Protocol Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Protocol Fee | 500 bps (5%) | 0 - 1000 bps | Deducted from each reward |
| Reward Rate | 10 bps (0.1%) | Configurable | Base reward as % of swap volume |
| Max Reward | 1000 FIX | Configurable | Cap per referral |
| Min Swap Amount | 100 | Configurable | Minimum volume to qualify |
| Max FIX Supply | 1,000,000,000 | Hard cap | Cannot be changed |
| Upgrade Timelock | 48 hours | Hard coded | Delay before upgrades execute |
| Fee Distribution | 50/30/20 | Configurable | Treasury / Buyback / Stakers |

---

## Architecture Summary

```
                    ┌─────────────────┐
                    │  Uniswap v4     │
                    │  PoolManager    │
                    └────────┬────────┘
                             │ afterSwap callback
                             ▼
                    ┌─────────────────┐
                    │  FixerHookV2    │  ← CREATE2-mined address
                    │  (per pool)     │     with AFTER_SWAP flag
                    └────────┬────────┘
                             │ recordReferral()
                             ▼
                    ┌─────────────────┐
                    │  ERC1967 Proxy  │  ← Users interact here
                    │  (Registry)     │     ERC-20 FIX token
                    │                 │     Tier management
                    │                 │     Fee collection
                    └────────┬────────┘
                             │ delegates to
                             ▼
                    ┌─────────────────┐
                    │  FixerRegistry  │
                    │  Upgradeable    │  ← UUPS implementation
                    │  (logic)        │     48h timelock upgrades
                    └─────────────────┘

                    ┌─────────────────┐
                    │ FixerCredential │  ← Soulbound ERC-721
                    │  (NFT)          │     On-chain SVG artwork
                    └─────────────────┘
```

---

## Reactive Network Integration Notes

The Fixer Protocol is designed for cross-chain operation via Reactive Network:

| | Testnet (Lasna) | Mainnet |
|---|---|---|
| Base | Supported | Supported |
| Arbitrum | Not supported | Supported |
| Unichain | Not supported | Supported |
| Ethereum | Supported | Supported |

**For testnet Reactive integration:** Use the **Base Sepolia** deployment as the primary origin chain. The Lasna testnet (chain ID 5318007) supports Base Sepolia (84532) and Ethereum Sepolia (11155111) as origin/destination chains.

**Reactive Callback Proxy (Base Sepolia):** `0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6`

---

## Deployment Scripts

| Script | Network | Command |
|--------|---------|---------|
| `DeployBaseSepolia.s.sol` | Base Sepolia | `forge script script/DeployBaseSepolia.s.sol --rpc-url base_sepolia --broadcast -vvvv` |
| `DeployArbSepolia.s.sol` | Arbitrum Sepolia | `forge script script/DeployArbSepolia.s.sol --rpc-url arb_sepolia --broadcast -vvvv` |
| `DeployUnichainSepolia.s.sol` | Unichain Sepolia | `forge script script/DeployUnichainSepolia.s.sol --rpc-url unichain_sepolia --broadcast -vvvv` |
| `DeployTestnet.s.sol` | Any (env-configured) | `forge script script/DeployTestnet.s.sol --rpc-url <RPC> --broadcast -vvvv` |

### Environment Variables Required

```bash
# Required
PRIVATE_KEY=0x...              # Deployer private key

# Optional (defaults to deployer)
SECURITY_COUNCIL=0x...         # Multisig for emergency pause
GOVERNANCE=0x...               # DAO governance (default: address(0))
```

### RPC Configuration (foundry.toml)

```toml
[rpc_endpoints]
base_sepolia = "${BASE_SEPOLIA_RPC}"
arb_sepolia = "${ARB_SEPOLIA_RPC}"
unichain_sepolia = "${UNICHAIN_SEPOLIA_RPC}"
```

---

## Deployment Records

Full deployment records with all addresses and verification data are stored in:

- [`deployments/base-sepolia.json`](../deployments/base-sepolia.json)
- [`deployments/arb-sepolia.json`](../deployments/arb-sepolia.json)
- [`deployments/unichain-sepolia.json`](../deployments/unichain-sepolia.json)

---

## Security Considerations

- **All interactions go through the Proxy address**, never the implementation directly
- The hook uses `try/catch` around `registry.recordReferral()` — a registry failure never blocks a swap
- Hook addresses are CREATE2-mined with **exact flag matching** (14-bit mask `0x3FFF`) to prevent extra permission bits
- The registry uses a 48-hour timelock on upgrades with `proposeUpgrade()` / `executeUpgrade()`
- Emergency pause is available via the Security Council multisig
- FIX token has a hard supply cap of 1 billion tokens
- Self-referral is blocked (referrer cannot equal swapper)

---

## Troubleshooting

### "HookAddressNotValid" during deployment

The mined hook address has extra permission bits set. The `HookMiner` uses exact flag matching (`address & 0x3FFF == flags`) to prevent this. If you see this error, ensure you're using the updated HookMiner with `ALL_HOOK_MASK`.

### "Hook address mismatch" during deployment

Foundry's `new Contract{salt}()` uses the deterministic CREATE2 deployer at `0x4e59b44847b379578588920cA78FbF26c0B4956C`, not the EOA deployer. Ensure `HookMiner.find()` is called with the CREATE2 deployer address.

### Contract size exceeds 24576 bytes

Enable `via_ir = true` in `foundry.toml`. The Yul IR pipeline produces smaller bytecode for complex contracts like FixerRegistryUpgradeable.

### No testnet ETH for Unichain Sepolia

Bridge ETH from Ethereum Sepolia via the OptimismPortal at `0x0d83dab629f0e0F9d36c0Cbc89B69a489f0751bD`:

```bash
cast send 0x0d83dab629f0e0F9d36c0Cbc89B69a489f0751bD \
  --value 0.3ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $ETHEREUM_SEPOLIA_RPC
```
