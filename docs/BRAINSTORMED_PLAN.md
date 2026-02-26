# FixerHook Brainstormed Plan

> Consolidated roadmap, architecture decisions, and feature plan for the FixerHook referral reward system.

**Document Version:** 2.6.0
**Created:** February 23, 2026
**Status:** Active Development
**Source Documents:** `internal/ENHANCEMENT_BRAINSTORM.md`, `internal/FUTURE_ENHANCEMENTS.md`, `internal/MARKET_SENTIMENT_ANALYSIS.md`, `internal/UPGRADEABILITY_AND_AI_AGENTS.md`, `internal/IMPLEMENTATION_TASKS.md`, `internal/X402_ENHANCEMENT_ANALYSIS.md`

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Core Philosophy](#2-core-philosophy)
3. [Version History](#3-version-history)
4. [Finalized Architecture Decisions](#4-finalized-architecture-decisions)
5. [System Architecture](#5-system-architecture)
6. [Feature Roadmap](#6-feature-roadmap)
7. [Token Economics](#7-token-economics)
8. [AI Agent Integration](#8-ai-agent-integration)
9. [Cross-Chain Strategy](#9-cross-chain-strategy)
10. [Governance & DAO](#10-governance--dao)
11. [Security Model](#11-security-model)
12. [Ecosystem Integrations](#12-ecosystem-integrations)
13. [Gap Analysis & New Ideas](#13-gap-analysis--new-ideas)
14. [Implementation Progress](#14-implementation-progress)
15. [ERC-8004 Clarification](#15-erc-8004-clarification)

---

## 1. Project Overview

**The Fixer Hook** is a production-grade referral reward system for Uniswap v4, implementing the **Side-Effect Tokenization** pattern. The core premise: frontends, aggregators, and referrers drive liquidity to pools but receive no on-chain compensation. This hook creates an on-chain affiliate system where referrers earn FIX tokens automatically when users swap through their referral links.

**Key principle:** The hook is observation-only. It does not modify swap parameters, extract fees, or change the user experience. Rewards are newly minted FIX tokens (not extracted from swaps), eliminating the fee-vs-referrer incentive misalignment.

### Current State

| Metric | Value |
|--------|-------|
| **Tests** | 381 passing across 35 suites |
| **Coverage** | 98.69% |
| **Gas (referral processing)** | ~140,875 avg |
| **Live testnets** | Base Sepolia, Arbitrum Sepolia, Unichain Sepolia, Lasna (Reactive Network) |
| **Architecture** | UUPS proxy + DELEGATECALL Extension + lightweight per-pool hooks |

---

## 2. Core Philosophy

**"Everybody pays the Fixer."**

The project follows these design principles:

1. **Observation-only hooks** — `afterSwap` only; never modify swap amounts or extract fees from users.
2. **Side-Effect Tokenization** — Rewards are a side-effect of legitimate DeFi activity, not a tax on it.
3. **Separation of concerns** — FIX token is immutable (user trust); Registry is upgradeable (logic flexibility).
4. **Progressive decentralization** — Owner-controlled at launch, transitioning to DAO governance.
5. **AI-agent-ready** — First-class support for autonomous agents as referrers and participants.

---

## 3. Version History

### Completed

| Version | Feature | Key Components |
|---------|---------|----------------|
| **v1.0** | Fixed Rewards | 10 FIX per referral, monolithic `FixerHook.sol` |
| **v1.1** | Dynamic Rewards | Volume-based calculation, min/max bounds, `rewardRateBps` |
| **v1.2** | Tiered System | Bronze/Silver/Gold/Platinum tiers with 1.0x-2.0x multipliers |
| **v2.0** | Cross-Pool Tracking | `FixerRegistry` + lightweight `FixerHookV2` per-pool hooks |
| **v2.1** | NFT Credentials | Soulbound `FixerCredential` (ERC-721 + ERC-5192), on-chain SVG |
| **v2.2** | UUPS + AI Agents | `FixerRegistryUpgradeable`, ERC-7201 storage, agent types, 48hr timelock |
| **v2.4** | Emergency Module | Circuit breakers (1M FIX/hr, 10M FIX/day), granular pause states |
| **v2.5** | Reactive Modular Architecture | DELEGATECALL Extension pattern (Core 20.5KB + Extension 14.7KB), FixerLib external library, EIP-170 split |
| **v2.6** | XMTP Communication & Agent Infrastructure Stack | XMTP wallet-to-wallet messaging, x402/EIP-3009 gasless payments, full ERC-8004 integration |

### Architectural Evolution

```
v1.0 (Monolithic)           v2.6+ (Modular + DELEGATECALL Extension)
┌──────────────────┐        ┌─────────────────────────────────────────┐
│   FixerHook.sol  │        │ ERC1967Proxy (user-facing)              │
│   BaseHook       │        │   └─ FixerRegistryUpgradeable (20.5KB)  │
│   + ERC20        │   →    │       ├─ ERC20 (FIX token, 1B supply)   │
│   + Stats        │        │       ├─ Tier system + rewards          │
│   + Rewards      │        │       ├─ EmergencyModule                │
│   755 lines      │        │       ├─ ERC-7201 storage (38-slot gap) │
└──────────────────┘        │       └─ fallback → DELEGATECALL ───┐   │
                            ├─────────────────────────────────────┤   │
                            │ FixerRegistryExtension (14.7KB)   ◄─┘   │
                            │   ├─ Agent registration (ERC-8004)      │
                            │   ├─ XMTP endpoint management          │
                            │   └─ EIP-3009 gasless transfers         │
                            ├─────────────────────────────────────────┤
                            │ FixerLib (2.3KB external library)       │
                            ├─────────────────────────────────────────┤
                            │ FixerHookV2 (per-pool, 4.5KB)          │
                            │   └─ afterSwap → registry.recordReferral│
                            ├─────────────────────────────────────────┤
                            │ FixerCredential (soulbound NFT, ERC-5192)│
                            └─────────────────────────────────────────┘
```

---

## 4. Finalized Architecture Decisions

These decisions were made based on market research documented in `internal/MARKET_SENTIMENT_ANALYSIS.md`.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Token upgradeability** | FIX = Non-upgradeable; Registry = UUPS | User trust ("code is law") + logic flexibility. Industry standard: UNI, AAVE tokens are immutable. |
| **Contract splitting** | Core (20.5KB) + Extension (14.7KB) via DELEGATECALL | EIP-170 compliance; shared ERC-7201 storage; single proxy address |
| **Agent registration** | ERC-8004 permissionless (NFT ownership proof) | No staking barrier; trust established via reputation, not capital |
| **Protocol fee** | 5% at launch, DAO-governed (max 10% hard cap) | Competitive with StakeWise V3 (5%); sustainable revenue. |
| **Bridge technology** | Reactive Network + Hyperlane + LayerZero OFT | Complementary stack: Reactive=automation, Hyperlane=data sync, LayerZero=token bridging. |

---

## 5. System Architecture

### Production Stack (v2.2+)

```
                    ┌──────────────────────────────────────────┐
                    │           ERC1967 Proxy                   │
                    │  ┌────────────────────────────────────┐   │
                    │  │  FixerRegistryUpgradeable (impl)   │   │
                    │  │  ├─ Initializable                  │   │
                    │  │  ├─ UUPSUpgradeable                │   │
                    │  │  ├─ OwnableUpgradeable             │   │
                    │  │  ├─ ERC20Upgradeable (FIX, 1B)     │   │
                    │  │  ├─ ReentrancyGuardUpgradeable     │   │
                    │  │  ├─ EIP712Upgradeable              │   │
                    │  │  ├─ EmergencyModule                │   │
                    │  │  └─ IAgentRegistry                 │   │
                    │  └────────────────────────────────────┘   │
                    │  Storage: FixerRegistryStorage (ERC-7201) │
                    │  Library: BPSMath, FixedPointMathLib      │
                    └──────────────┬───────────────────────────┘
                                   │ recordReferral()
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
  ┌───────┴────────┐   ┌──────────┴───────┐   ┌───────────┴──────┐
  │ FixerHookV2    │   │ FixerHookV2      │   │ FixerHookV2      │
  │ (Pool A)       │   │ (Pool B)         │   │ (Pool C)         │
  │ afterSwap only │   │ afterSwap only   │   │ afterSwap only   │
  └────────────────┘   └──────────────────┘   └──────────────────┘

  FixerCredential (ERC-721 + ERC-5192 soulbound, on-chain SVG)
```

### Swap Flow

1. User initiates swap with `hookData = abi.encode(referrerAddress)`
2. `FixerHookV2.afterSwap()` fires (observation-only)
3. Hook decodes referrer, calculates volume in quote token
4. Hook calls `registry.recordReferral(referrer, swapper, volume, poolId)`
5. Registry applies tier multiplier, mints FIX to referrer
6. Registry checks circuit breaker thresholds
7. Tier auto-upgrades if thresholds met

---

## 6. Feature Roadmap

### Planned Versions

| Version | Feature | Dependencies | Status |
|---------|---------|--------------|--------|
| **v2.5** | Reactive Modular Architecture (DELEGATECALL Extension + FixerLib) | v2.4 | ✅ Complete |
| **v2.6** | XMTP Communication + Agent Infrastructure Stack | v2.5 | ✅ Complete |
| **v2.7** | FIX Token Staking (veFIX) + Governance | v2.6 | Planned |
| **v2.8** | Referrer Teams & Reputation System | v2.7 | Planned |
| **v2.9** | AI Agent Marketplace + Multi-Agent Chains | v2.7 | Planned |
| **v3.0** | Cross-Chain Token Bridge & Leaderboards + Full DAO | v2.7 | Future |

### Dependency Graph

```
v1.2 (Tiers) ─── v2.0 (Cross-Pool) ─┬─ v2.1 (NFT Credentials)
                                      ├─ v2.2 (UUPS + AI) ─────┬─ v2.3 (Reactive Network)
                                      │                         ├─ v2.4 (Emergency)
                                      │                         ├─ v2.5 (DELEGATECALL Extension) ✅
                                      │                         └─ v2.6 (XMTP + Agent Stack) ✅
                                      └─ v2.4 (Emergency)
                                                                     │
                                      v2.6 ──────────────── v2.7 (Staking + DAO)
                                                                     │
                                                              v2.8+ (Teams, Marketplace, Bridge)
```

---

## 7. Token Economics

### FIX Token

| Property | Value |
|----------|-------|
| **Name** | Fixer Token (FIX) |
| **Supply** | 1,000,000,000 (1B) |
| **Standard** | ERC-20 (non-upgradeable) |
| **Decimals** | 18 |
| **Minting** | By registry on referral events |

### Reward Calculation

```
baseReward = (swapVolume * rewardRateBps) / 10000
clampedReward = clamp(baseReward, minRewardAmount, maxRewardAmount)
finalReward = (clampedReward * tierMultiplierBps) / 10000
netReward = finalReward * (1 - protocolFeeBps / 10000)
```

### Tier System

| Tier | Min Volume | Min Referrals | Multiplier |
|------|-----------|---------------|------------|
| Bronze | $0 | 0 | 1.0x |
| Silver | $10,000 | 10 | 1.25x |
| Gold | $100,000 | 50 | 1.5x |
| Platinum | $1,000,000 | 200 | 2.0x |

### Protocol Fee Distribution (Planned)

| Destination | Share | Purpose |
|-------------|-------|---------|
| Treasury | 50% | Development, audits |
| Buyback & Burn | 30% | FIX value accrual |
| Staker Rewards | 20% | veFIX holder yield |

### veFIX Staking (Planned v2.5)

| Lock Period | Multiplier | Revenue Share |
|-------------|------------|---------------|
| 30 days | 1.1x | 1% |
| 90 days | 1.25x | 3% |
| 180 days | 1.5x | 5% |
| 365 days | 2.0x | 10% |

---

## 8. AI Agent Integration

### Agent Tiers (Finalized)

| Tier | Stake | Multiplier | Slashing | Chains |
|------|-------|------------|----------|--------|
| Unverified | 0 FIX | 0x (no rewards) | N/A | Testing only |
| Starter | 100 FIX | 1.0x | 10% (10 FIX) | 1 chain |
| Professional | 1,000 FIX | 1.25x | 15% (150 FIX) | 5 chains |
| Enterprise | 10,000 FIX | 1.5x | 20% (2,000 FIX) | Unlimited |
| Audited | 10,000 FIX + audit | 2.0x | 5% (500 FIX) | Unlimited + featured |

### Agent Types

- **Trading Agent** — Automated swaps, arbitrage, MEV capture
- **Social Agent** — Recommendations, influencer, education
- **Portfolio Agent** — Rebalancing, DCA strategies, yield farming
- **Aggregator** — Cross-protocol routing
- **Custom** — User-defined

### Agent Reward Split

For agent-facilitated referrals, rewards are split:
- **70%** to the human referrer
- **30%** to the AI agent

Both shares are further modified by the respective tier multipliers.

### Multi-Agent Referral Chains (Planned v2.7)

```
Human Referrer (10%) → AI Agent A (30%) → AI Agent B (20%) → End User (swaps)
                                                                    ↓
                                                            FIX Rewards Distributed
                                                            Protocol Treasury (40%)
```

### Agent Marketplace (Planned v2.7)

- Featured agents based on volume, reputation, and verification level
- Verification badges: Verified (audited + staked), Registered (staked), Unverified
- Agent performance metrics: volume generated, users served, success rate

---

## 9. Cross-Chain Strategy

### Architecture

The cross-chain stack uses three complementary technologies:

| Technology | Role | Use Case |
|------------|------|----------|
| **Reactive Network** | Event automation | Subscribe to referral events across chains, aggregate volume, trigger tier upgrades |
| **Hyperlane** | Data/callback sync | Registry synchronization, tier updates, stats sync (custom ISM) |
| **LayerZero OFT** | Token bridging | Canonical FIX token transfer across chains (burn/mint model) |

### Supported Chains (Deployed)

| Chain | Registry Proxy | FixerHookV2 | FixerCredential |
|-------|---------------|-------------|-----------------|
| Base Sepolia | `0x3Fb805C6C01e8Dd8534fA9FD52Ee699e256Eb960` | `0x92Cb...040` | `0xd2fD5c...3ef` |
| Arbitrum Sepolia | `0x07dF8c1c6d5Fc2109bf442dFBc1e7050eDf4f9Eb` | `0x7A5E4C...040` | `0x0F94b6...c79` |
| Unichain Sepolia | `0xa5589Eed2A8831eEFbCdD39BF9FE59D6ef4344d9` | `0x983eA9...040` | `0x88a31b...5c0` |
| Lasna (Reactive) | `0xd2f11a95F1ca8cc94FB63926dc3A92655aAc6fF3` | N/A (registry-only) | N/A |

### Cross-Chain Leaderboards (Planned v2.8)

- Top 100 referrers updated hourly via Reactive Network callbacks
- Aggregated volume, referral count, and earned rewards across all chains

---

## 10. Governance & DAO

### Governance Scope

| Category | Governable Parameters |
|----------|----------------------|
| **Reward parameters** | Reward rate, tier thresholds, tier multipliers, min swap amount |
| **Agent parameters** | Agent reward splits, staking requirements |
| **Protocol fees** | Fee percentage (within 0-10% cap), fee distribution ratios |
| **Upgrades** | Implementation upgrades (with 48hr timelock), new modules |
| **Treasury** | Grant distribution, buyback programs |

### Proposal Lifecycle

```
PROPOSE (7 days) → REVIEW (3 days) → VOTE (7 days) → TIMELOCK (48 hrs) → EXECUTE
```

### Voting Power

```
votingPower = fixBalance * (1 + durationMultiplier)
```

- 1K FIX unstaked = 1,000 votes
- 1K FIX staked 30d = 1,100 votes (1.1x)
- 1K FIX staked 1yr = 2,000 votes (2.0x)

---

## 11. Security Model

### Implemented Protections

| Protection | Mechanism |
|------------|-----------|
| **Circuit breaker** | Auto-pause if >1M FIX minted/hour or >10M FIX/day |
| **Granular pause** | Independent pause for referrals, agents, and rewards |
| **Upgrade timelock** | 48-hour delay between proposal and execution |
| **Self-referral prevention** | Referrer cannot equal swapper |
| **Reentrancy guard** | OpenZeppelin ReentrancyGuard on state-changing functions |
| **Storage safety** | ERC-7201 namespaced storage with 38-slot gap |
| **Initialization safety** | `_disableInitializers()` in implementation constructor |

### Emergency Module

- **Security council** can pause immediately
- **Pause > 7 days** requires DAO vote to resume
- **Circuit breaker** triggers automatically on anomalous minting
- All pause states are independent (referrals, agents, rewards)

### Agent Security

| Risk | Mitigation |
|------|------------|
| Sybil agents | ERC-8004 NFT identity + reputation scoring |
| Malicious agents | Reputation degradation + validation registry |
| Agent impersonation | ERC-8004 NFT ownership proof + agentWallet verification |
| Wash trading | Volume caps + graph analysis |
| MEV extraction | Flashbots integration (optional) |

---

## 12. Ecosystem Integrations

### DeFi Protocol Integrations (Planned)

| Protocol | Type | Value |
|----------|------|-------|
| **Chainlink** | Price oracles | Accurate volume measurement in USD terms |
| **ENS** | Identity | Referrer identity via human-readable names |
| **Safe (Gnosis)** | Multi-sig | Team referrer wallets |
| **ERC-4337 Bundlers** | Account Abstraction | Agent wallets, gas sponsorship |
| **The Graph** | Indexing | Analytics and referral data access |
| **Push Protocol** | Notifications | Referral and tier-upgrade notifications |

### x402 Protocol Integration (Planned v2.4/v2.5)

x402 (Coinbase's HTTP 402 payment standard) enables **Referral-as-a-Service (RaaS)**:
- AI agents pay micropayments (USDC on Base) to access premium referral data
- Agent-to-agent micropayments for referral placement and reward optimization
- Native MCP server support for AI agent discovery

### L2 Priority

| Chain | Priority | Rationale |
|-------|----------|-----------|
| Unichain | High | Uniswap-native chain |
| Base | High | Coinbase ecosystem, x402 alignment |
| Arbitrum | High | Largest L2 by TVL |
| Optimism | Medium | OP Stack |

---

## 13. Gap Analysis & New Ideas

### Identified Gaps (from brainstorming)

| Gap | Priority | Status |
|-----|----------|--------|
| DELEGATECALL Extension | High | ✅ Complete (v2.5) |
| XMTP + Agent Infrastructure Stack | High | ✅ Complete (v2.6) |
| Emergency Pause | High | ✅ Complete (v2.4) |
| Token Staking (veFIX) | High | Planned (v2.7) |
| Governance Module | High | Planned (v2.7) |
| Protocol Fee Collection | High | Planned (v2.7) |
| Referrer Teams | Medium | Planned (v2.8) |
| MEV Protection | Medium | Planned (v3.1) |
| SDK/Library | Medium | Planned |
| Gamification (Achievements) | Low | Planned (v2.8) |
| Time-Based Decay | Low | Under consideration |
| Oracle Integration | Medium | Planned |

### New Feature Ideas

**Achievement System (v2.6)**
- Volume achievements: $1K Starter, $10K Growing, $100K Whale Maker, $1M Legend
- Referral achievements: 1 Fixer, 10 Connector, 50 Influencer, 200 Community Leader
- Streak achievements: 7-day, 30-day, 100-day active streaks
- Special: Early Adopter, Cross-Chain Pioneer, AI Collaborator, Bug Hunter

**Quest System (via Reactive Network)**
- Quests with target volume/referrals/active days
- FIX rewards on completion, verified by Reactive Network callbacks
- Time-limited with expiry dates

**Referrer Teams (v2.6)**
- Team bonuses: 2.5% (Bronze) to 10% (Platinum)
- Leader gets 40-50% of team bonus pool
- Inactive teams dissolve after 90 days
- No multi-team membership

---

## 14. Implementation Progress

### Epic Tracker

| Epic | Version | Tasks | Done | Progress |
|------|---------|-------|------|----------|
| UUPS Infrastructure | v2.2.1 | 6 | 6 | 100% |
| Emergency Module | v2.4 | 2 | 2 | 100% |
| DELEGATECALL Extension + FixerLib | v2.5 | 4 | 4 | 100% |
| XMTP + Agent Infrastructure Stack | v2.6 | 3 | 3 | 100% |
| ERC-8004 Agent Registration | v2.6 | 4 | 4 | 100% |
| Reactive Network Core | v2.3.1 | 3 | 0 | 0% |
| Hyperlane Integration | v2.3.2 | 3 | 0 | 0% |
| LayerZero OFT Bridge | v3.0 | 2 | 0 | 0% |
| Staking (veFIX) | v2.7 | 1 | 0 | 0% |
| Governance Module | v2.7 | 1 | 0 | 0% |
| Protocol Fee System | v2.7 | 1 | 0 | 0% |
| Referrer Teams | v2.8 | 2 | 0 | 0% |
| AI Agent Marketplace | v2.9 | TBD | 0 | 0% |
| **Total** | | **32+** | **19** | **~60%** |

### Sprint Plan

| Sprint | Focus | Scope |
|--------|-------|-------|
| Sprint 1 | Foundation | UUPS Infrastructure + Emergency Module |
| Sprint 2 | AI Agents | Agent Registration + Staking Tiers |
| Sprint 3 | Cross-Chain Core | Reactive Network + Hyperlane |
| Sprint 4 | Staking & Governance | veFIX + DAO + Protocol Fees |
| Sprint 5 | Teams & Marketplace | Referrer Teams + AI Marketplace |

---

## 15. ERC-8004 Clarification

Several internal documents reference "ERC-8004" alignment for the agent staking model. This section clarifies the actual relationship.

### What ERC-8004 Actually Is

**ERC-8004: "Trustless Agents"** is a **Draft** EIP (created August 13, 2025) authored by contributors from MetaMask, Ethereum Foundation, Google, and Coinbase. It defines three lightweight registries for agent discovery and trust:

1. **Identity Registry** — ERC-721 NFTs as portable agent identifiers with metadata endpoints (A2A, MCP, ENS, DID, etc.) and a cryptographically verified `agentWallet` field.

2. **Reputation Registry** — On-chain feedback signals with fixed-point scoring, tags, and off-chain detail references. Clients submit feedback; registries aggregate it.

3. **Validation Registry** — Framework for independent validator checks (re-execution, zkML, TEE attestation) with scored responses (0-100).

### What It Does NOT Specify

ERC-8004 **explicitly states** that "incentives and slashing related to validation are managed by the specific validation protocol and are **outside the scope of this registry**." This means:

- It does **not** prescribe staking amounts (100 FIX, 1,000 FIX, etc.)
- It does **not** define slashing rates or mechanisms
- It does **not** specify agent tier structures
- It does **not** mandate any particular token economics

### Where Internal Docs Diverge

| Internal Claim | Actual ERC-8004 |
|----------------|-----------------|
| "ERC-8004 Aligned: Stake proportional to risk/activity level" | ERC-8004 does not specify staking amounts or proportionality rules. Staking is explicitly out of scope. |
| Called "Ethereum Agent Identity Standard" | Actual title is "Trustless Agents" — covers identity, reputation, AND validation. |
| Staking tiers described as "ERC-8004 aligned" | The tiered staking model is the project's own design. ERC-8004 provides registries, not staking frameworks. |

### Genuine Alignment Opportunities

Despite the mischaracterization of staking alignment, there are real integration points:

| ERC-8004 Component | FixerHook Integration |
|--------------------|----------------------|
| **Identity Registry (ERC-721)** | Register agents as NFTs for cross-platform discovery. Similar to `FixerCredential` but transferable (ERC-8004) vs. soulbound (ERC-5192). |
| **Reputation Registry** | Publish referral performance (volume, count, success rate) as on-chain feedback signals. |
| **Validation Registry** | Use validator checks for agent verification (alternative to current stake-only model). |
| **Agent endpoints** | Expose A2A/MCP endpoints for agent-to-agent referral coordination. |
| **`agentWallet` field** | Map to the existing `AgentInfo.operator` field for payment routing. |

### Recommendation

1. **Correct internal docs:** Remove "ERC-8004 aligned" claims from staking model descriptions. The staking model is valid on its own merits without misattributing it to ERC-8004.
2. **Plan genuine integration:** In v2.7 (AI Agent Marketplace), consider implementing ERC-8004's Identity Registry interface for agent registration. This would make FixerHook agents discoverable by any ERC-8004-compatible system.
3. **Monitor draft status:** ERC-8004 is still a Draft. Interface changes are possible before finalization. Track progress at [EIP-8004](https://eips.ethereum.org/EIPS/eip-8004).

---

## Related Documents

| Document | Location | Purpose |
|----------|----------|---------|
| System Design | `docs/SYSTEM_DESIGN.md` | Architecture deep-dive |
| Integration Guide | `docs/INTEGRATION_GUIDE.md` | Frontend integration |
| Security | `docs/SECURITY.md` | Threat model and mitigations |
| Testing | `docs/TESTING.md` | Test patterns and coverage |
| Deployment | `docs/DEPLOYMENT.md` | Deployment procedures |
| Research Paper | `docs/RESEARCH_PAPER.md` | IEEE/ACM-style academic paper |
| Enhancement Brainstorm | `internal/ENHANCEMENT_BRAINSTORM.md` | Full brainstorm details |
| Market Sentiment Analysis | `internal/MARKET_SENTIMENT_ANALYSIS.md` | Research backing decisions |
| UUPS & AI Agents | `internal/UPGRADEABILITY_AND_AI_AGENTS.md` | v2.2 technical specs |
| x402 Analysis | `internal/X402_ENHANCEMENT_ANALYSIS.md` | x402 integration strategy |
| Implementation Tasks | `internal/IMPLEMENTATION_TASKS.md` | Sprint task breakdown |

---

*This document consolidates the brainstormed plans from internal planning documents into a single reference. For detailed implementation specs, refer to the linked internal documents.*
