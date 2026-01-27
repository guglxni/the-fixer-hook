# The Referral Hook

> On-chain Affiliate Links for Uniswap v4 — Turn any liquidity pool into a viral growth engine.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-363636?style=for-the-badge&logo=solidity)](https://soliditylang.org/)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-FF007A?style=for-the-badge&logo=uniswap)](https://uniswap.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

---

## Overview

The **Referral Hook** transforms Uniswap v4 liquidity pools into **decentralized affiliate marketing engines**. When a user executes a swap, they can pass a referrer's address via the `hookData` parameter. The hook then rewards that referrer with freshly minted `REF` tokens — creating a powerful incentive mechanism for organic growth.

### Key Features

| Feature | Description |
|---------|-------------|
| **Zero-Overhead Swaps** | Operates as a side-effect; swap execution remains unchanged |
| **Native Token Rewards** | Mints `REF` tokens directly to referrers |
| **Sybil-Resistant** | Built-in checks prevent self-referral exploitation |
| **Gas-Optimized** | Only `afterSwap` permission enabled — minimal gas overhead |
| **Plug-and-Play** | Simple frontend integration via `hookData` encoding |

---

## Architecture

```
                              SWAP WORKFLOW

    +----------+         +---------------+         +----------------+
    | Frontend | --1-->  |  SwapRouter   | --2-->  |  PoolManager   |
    |  (dApp)  |         |               |         |                |
    +----------+         +---------------+         +-------+--------+
         |                                                 |
         | Encodes referrer                                |
         | in hookData                                     | 3. Executes swap
         |                                                 |
         |                                                 v
         |                                         +----------------+
         |                                         |  afterSwap()   |
         |                                         |                |
         |                                         |  ReferralHook  |
         |                                         +-------+--------+
         |                                                 |
         |                                                 | 4. Validates & mints
         |                                                 v
         |                                         +----------------+
    <----+-----------------------------------------|   REF Token    |
         |           6. Referrer earns             |    Minted      |
         |              REF tokens                 +----------------+
    +----------+
    | Referrer |
    | (Wallet) |
    +----------+
```

### Architectural Pattern: Side-Effect Tokenization

The hook operates **non-invasively** — it doesn't modify swap parameters, take fees, or alter expected outcomes. Instead, it triggers a side-effect (token minting) based on validated referral data. This ensures:

- Users experience **standard swap behavior**
- Referrers are rewarded **without impacting swap costs**
- System complexity remains **minimal and auditable**

---

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest)
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/the-referral-hook.git
cd the-referral-hook

# Install dependencies
forge install

# Build
forge build

# Run tests
forge test -vvv
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
| [**System Design**](./docs/SYSTEM_DESIGN.md) | High-Level & Low-Level design specifications |
| [**Implementation Guide**](./docs/IMPLEMENTATION_GUIDE.md) | Step-by-step coding walkthrough |
| [**Integration Guide**](./docs/INTEGRATION_GUIDE.md) | Frontend & backend integration patterns |
| [**Security Analysis**](./docs/SECURITY.md) | Threat model and mitigation strategies |
| [**Testing Strategy**](./docs/TESTING.md) | Test cases and coverage requirements |
| [**Deployment Guide**](./docs/DEPLOYMENT.md) | Mainnet/L2 deployment procedures |

---

## How It Works

### 1. Encoding Referral Data (Frontend)

```typescript
import { ethers } from 'ethers';

const referrerAddress = "0x..."; // The referrer's wallet
const hookData = ethers.utils.defaultAbiCoder.encode(
  ['address'],
  [referrerAddress]
);

// Pass hookData to swap transaction
await router.swap(poolKey, swapParams, hookData);
```

### 2. Processing Referrals (Smart Contract)

```solidity
function _afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) internal override returns (bytes4, int128) {
    
    if (hookData.length > 0) {
        address referrer = abi.decode(hookData, (address));
        
        // Prevent gaming: no self-referrals
        if (referrer != address(0) && referrer != tx.origin) {
            _mint(referrer, REWARD_AMOUNT);
        }
    }
    
    return (BaseHook.afterSwap.selector, 0);
}
```

---

## Token Economics

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Token Name** | Referral Token | |
| **Symbol** | REF | |
| **Decimals** | 18 | Standard ERC-20 |
| **Reward per Swap** | 10 REF | Configurable |
| **Total Supply** | Unlimited (Mint-only) | Can be capped in future versions |

---

## Security Considerations

### Built-in Protections

| Attack Vector | Mitigation |
|---------------|------------|
| **Self-Referral** | Block `tx.origin == referrer` |
| **Zero Address** | Skip minting for `address(0)` |
| **Empty Data** | Graceful fallback for non-referral swaps |

### Known Limitations

| Risk | Severity | Notes |
|------|----------|-------|
| **Sybil Attacks** | Medium | Users with multiple wallets can farm tokens |
| **Gas Overhead** | Low | ~23k gas added per referral (L2 negligible) |
| **tx.origin Usage** | Medium | Acceptable for anti-gaming; not for auth |

> See [Security Analysis](./docs/SECURITY.md) for comprehensive threat modeling.

---

## Roadmap

- [x] **Phase 1** — MVP Implementation (Fixed rewards)
- [ ] **Phase 2** — Dynamic rewards based on swap volume
- [ ] **Phase 3** — Multi-tier referral system (MLM-style)
- [ ] **Phase 4** — Governance token integration
- [ ] **Phase 5** — Cross-chain referral tracking

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](./CONTRIBUTING.md) for details on:

- Code style and conventions
- Pull request process
- Issue reporting

---

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

---

## Acknowledgments

- [Uniswap Labs](https://uniswap.org/) — For the revolutionary v4 architecture
- [Solmate](https://github.com/transmissions11/solmate) — For gas-optimized token contracts
- The broader DeFi community for continuous innovation

---

<p align="center">
  <strong>Built for the future of decentralized finance</strong>
</p>
