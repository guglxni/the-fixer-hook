# Integration Guide

> The Fixer Hook Protocol — Frontend, Agent, and Off-Chain Integration (v2.6.0)

**Last Updated:** February 26, 2026 | **Version:** 2.6.0

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Frontend Integration](#frontend-integration)
3. [Agent Integration (ERC-8004)](#agent-integration-erc-8004)
4. [Off-Chain Services](#off-chain-services)
5. [RaaS API](#raas-api)
6. [MCP Server (AI Agents)](#mcp-server-ai-agents)
7. [XMTP Integration](#xmtp-integration)
8. [Multi-Chain Support](#multi-chain-support)
9. [Error Handling](#error-handling)

---

## Quick Start

### 1. Encode Referrer in hookData

Every Uniswap v4 swap can include a referrer address via `hookData`:

```solidity
bytes memory hookData = abi.encode(referrerAddress);
// Pass hookData to Uniswap v4 swap router
```

That's it. The hook automatically validates the referrer and mints FIX tokens.

### 2. Read Referrer Stats

```solidity
interface IFixerRegistry {
    function getReferrerStats(address referrer) external view returns (
        uint128 totalVolume,
        uint64 referralCount,
        uint8 tier
    );
}
```

---

## Frontend Integration

### hookData Encoding

| Field | Type | Size | Description |
|-------|------|------|-------------|
| referrer | `address` | 32 bytes (ABI-encoded) | The referrer's wallet address |

#### Viem (Recommended)

```typescript
import { encodeAbiParameters, parseAbiParameters } from 'viem'

const hookData = encodeAbiParameters(
  parseAbiParameters('address'),
  [referrerAddress]
)
```

#### Ethers v6

```typescript
import { AbiCoder } from 'ethers'

const coder = new AbiCoder()
const hookData = coder.encode(['address'], [referrerAddress])
```

#### Ethers v5

```typescript
import { utils } from 'ethers'

const hookData = utils.defaultAbiCoder.encode(
  ['address'],
  [referrerAddress]
)
```

### URL-Based Referral Tracking

```typescript
// Extract referrer from URL: https://app.example.com/swap?ref=0xABC...
const params = new URLSearchParams(window.location.search)
const referrer = params.get('ref')

if (referrer && isAddress(referrer)) {
  hookData = encodeAbiParameters(
    parseAbiParameters('address'),
    [referrer]
  )
}
```

### React Component Example (Wagmi v2 + Viem)

```tsx
import { useAccount, useWriteContract } from 'wagmi'
import { encodeAbiParameters, parseAbiParameters, parseEther } from 'viem'

function SwapWithReferral({ referrer }: { referrer: `0x${string}` }) {
  const { address } = useAccount()
  const { writeContract } = useWriteContract()

  const handleSwap = () => {
    const hookData = encodeAbiParameters(
      parseAbiParameters('address'),
      [referrer]
    )

    writeContract({
      address: SWAP_ROUTER_ADDRESS,
      abi: swapRouterAbi,
      functionName: 'swap',
      args: [poolKey, swapParams, hookData],
    })
  }

  return <button onClick={handleSwap}>Swap</button>
}
```

### Displaying Referrer Info

```typescript
import { createPublicClient, http } from 'viem'
import { baseSepolia } from 'viem/chains'

const client = createPublicClient({
  chain: baseSepolia,
  transport: http()
})

// Read referrer stats
const stats = await client.readContract({
  address: REGISTRY_PROXY,
  abi: registryAbi,
  functionName: 'getReferrerStats',
  args: [referrerAddress]
})

// Read FIX balance
const fixBalance = await client.readContract({
  address: REGISTRY_PROXY,
  abi: registryAbi,
  functionName: 'balanceOf',
  args: [referrerAddress]
})
```

### Displaying Credential NFT

```typescript
// Read credential token URI (returns base64-encoded JSON with on-chain SVG)
const tokenUri = await client.readContract({
  address: CREDENTIAL_CONTRACT,
  abi: credentialAbi,
  functionName: 'tokenURI',
  args: [tokenId]
})

// Decode: data:application/json;base64,... → JSON → SVG
const metadata = JSON.parse(atob(tokenUri.split(',')[1]))
const svgImage = metadata.image // data:image/svg+xml;base64,...
```

---

## Agent Integration (ERC-8004)

### Register as an Agent

Agents register permissionlessly by proving ERC-8004 NFT ownership:

```solidity
// 1. Own an ERC-8004 identity NFT
// 2. Ensure agentWallet matches your address
// 3. Call registerAgent through the proxy

IAgentRegistry(REGISTRY_PROXY).registerAgent(
    agentId,           // uint256 — your ERC-8004 NFT token ID
    AgentPlatform.Custom  // 0=Human, 1=OpenClaw, 2=Moltbook, 3=Custom
);
```

```typescript
// Viem example
await walletClient.writeContract({
  address: REGISTRY_PROXY,
  abi: agentRegistryAbi,
  functionName: 'registerAgent',
  args: [agentId, 3n] // 3 = Custom platform
})
```

### Enable XMTP Communication

```solidity
IAgentRegistry(REGISTRY_PROXY).enableXMTP(
    publicKeyHash,     // bytes32 — keccak256 of XMTP public key
    "https://my-xmtp-endpoint.example.com"  // endpoint URI
);
```

### Delegate Referrals

```solidity
// Delegate your referral earnings to another address
IAgentRegistry(REGISTRY_PROXY).delegateReferral(delegateeAddress);

// Revoke delegation
IAgentRegistry(REGISTRY_PROXY).revokeDelegation();
```

### Gasless FIX Transfers (EIP-3009 / x402)

```typescript
import { signTypedData } from 'viem/accounts'

// Sign an EIP-712 authorization for gasless FIX transfer
const signature = await walletClient.signTypedData({
  domain: {
    name: 'Fixer Token',
    version: '1',
    chainId: 84532n,
    verifyingContract: REGISTRY_PROXY,
  },
  types: {
    TransferWithAuthorization: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'validAfter', type: 'uint256' },
      { name: 'validBefore', type: 'uint256' },
      { name: 'nonce', type: 'bytes32' },
    ],
  },
  primaryType: 'TransferWithAuthorization',
  message: { from, to, value, validAfter, validBefore, nonce },
})

// Anyone can submit the authorization (gasless for the signer)
await walletClient.writeContract({
  address: REGISTRY_PROXY,
  abi: extensionAbi,
  functionName: 'transferWithAuthorization',
  args: [from, to, value, validAfter, validBefore, nonce, v, r, s],
})
```

---

## Off-Chain Services

The protocol includes three off-chain services in the `x402/` directory:

| Service | Location | Stack | Description |
|---------|----------|-------|-------------|
| **RaaS API** | `x402/raas-server/` | Hono + @x402/server | REST API for pools, referrers, agents — micropayment-gated |
| **MCP Server** | `x402/mcp-server/` | @modelcontextprotocol/sdk | Tool server for AI assistants |
| **XMTP Bot** | `x402/xmtp-bot/` | @xmtp/node-sdk | Wallet-to-wallet messaging bot |

---

## RaaS API

### Endpoints

| Method | Path | Description |
|:------:|------|-------------|
| GET | `/api/v1/pools` | List all configured pools |
| GET | `/api/v1/referrers` | List referrer profiles |
| GET | `/api/v1/agents` | List registered agents |
| GET | `/api/v1/agents/xmtp/:addr` | Get agent's XMTP endpoint |
| GET | `/api/v1/agents/xmtp` | List all XMTP-enabled agents |
| POST | `/api/v1/optimize` | Calculate optimal referral strategy |

All `/api/*` routes are **gated by x402 USDC micropayments** (uses `@x402/server` middleware). Dev mode bypasses payment.

### Running

```bash
cd x402/raas-server
npm install
npm start  # Runs on port 3000
```

---

## MCP Server (AI Agents)

The MCP (Model Context Protocol) server exposes tools for AI agents like Claude or ChatGPT:

| Tool | Description |
|------|-------------|
| `query_pools` | Get pool configurations and stats |
| `check_referrer` | Look up referrer profile, tier, volume |
| `calculate_rewards` | Estimate FIX rewards for a given volume |
| `agent_analytics` | Agent registration and reputation data |
| `referral_intent` | Generate referral hookData for a swap |

### Running

```bash
cd x402/mcp-server
npm install
npm start  # Communicates via stdio
```

### Configuration

```env
RPC_URL=https://sepolia.base.org
REGISTRY_ADDRESS=0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960
CHAIN_ID=84532
```

---

## XMTP Integration

### On-Chain Discovery

```typescript
// Check if an agent has XMTP enabled
const enabled = await client.readContract({
  address: REGISTRY_PROXY,
  abi: agentRegistryAbi,
  functionName: 'isXMTPEnabled',
  args: [agentAddress]
})

// Get XMTP endpoint URL
const endpoint = await client.readContract({
  address: REGISTRY_PROXY,
  abi: agentRegistryAbi,
  functionName: 'getXMTPEndpoint',
  args: [agentAddress]
})

// Get total XMTP-enabled agents
const count = await client.readContract({
  address: REGISTRY_PROXY,
  abi: agentRegistryAbi,
  functionName: 'getXMTPEnabledCount',
})
```

### XMTP Bot

```bash
cd x402/xmtp-bot
npm install
npm start
```

The bot uses @xmtp/node-sdk (XMTP v3) for wallet-to-wallet encrypted messaging. It reads on-chain agent profiles and verification status.

---

## Multi-Chain Support

### Contract Addresses

| Chain | Registry Proxy | Hook | Credential |
|-------|---------------|------|------------|
| Base Sepolia (84532) | `0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960` | `0x2CE392Ba90fcAeE3CD23dBcFe11fC2Dc098A8040` | `0xB624bbeC6e044365d365A7f66A253abf27226f82` |
| Arb Sepolia (421614) | `0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb` | `0x1bf835D48d3a7743dc4A179B0bE2b9dD9a8cC040` | `0x72489A460c90210e0Cfb0d24B2646F10D38EAcc1` |
| Unichain Sepolia (1301) | `0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9` | `0x8D965484Bedb2CdEC65f919a91005b795c854040` | `0x3e0d0028DE34fbFe0365d52d9D5D955E0F193EBb` |
| Lasna (5318007) | `0xd2f11a95F1ca8cc94FB63926dc3A92655aAc6fF3` | — | `0xB9356961aa61AA1148f39Dd0C748656C3E574596` |

### Chain Selection

```typescript
import { baseSepolia, arbitrumSepolia } from 'viem/chains'

// Unichain Sepolia (custom chain)
const unichainSepolia = {
  id: 1301,
  name: 'Unichain Sepolia',
  rpcUrls: { default: { http: ['https://sepolia.unichain.org'] } },
}

// Lasna (Reactive Network — custom chain)
const lasna = {
  id: 5318007,
  name: 'Lasna',
  rpcUrls: { default: { http: ['https://lasna-rpc.rnk.dev/'] } },
}
```

> **Note:** Lasna has no PoolManager, so swap-related features are unavailable there. Only registry, agent, and credential operations work on Lasna.

---

## Error Handling

### Swap Errors

```typescript
try {
  await walletClient.writeContract({
    address: SWAP_ROUTER_ADDRESS,
    abi: swapRouterAbi,
    functionName: 'swap',
    args: [poolKey, swapParams, hookData],
  })
} catch (error) {
  // Hook errors are non-blocking — malformed hookData is caught via try/catch
  // The swap still succeeds; only the referral reward is skipped
  console.warn('Referral may not have been recorded:', error.message)
}
```

### Common Error Codes

| Error | Cause | Resolution |
|-------|-------|------------|
| `InvalidHookData` | hookData cannot be decoded as address | Fix ABI encoding |
| `SelfReferral` | Referrer === swapper | Use different referrer address |
| `MinSwapAmountNotMet` | Swap volume below pool threshold | Increase swap amount |
| `PausedReferrals` | Emergency pause active | Wait for resume |
| `NotAuthorizedHook` | Hook not registered in registry | Admin must call `registerHook()` |
| `TokenLocked` | Attempting to transfer soulbound credential | Credentials are non-transferable |

### Validation Best Practices

```typescript
function validateReferrer(referrer: string, swapper: string): boolean {
  if (!isAddress(referrer)) return false
  if (referrer === '0x0000000000000000000000000000000000000000') return false
  if (referrer.toLowerCase() === swapper.toLowerCase()) return false
  return true
}
```

---

<p align="center">
  <em>Document Version: 3.0.0 | Last Updated: February 26, 2026</em>
</p>
