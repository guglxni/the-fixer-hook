# Testing Strategy

> The Fixer Hook Protocol — Test Suite Documentation (v2.6.0)

**Last Updated:** February 26, 2026 | **381 tests across 35 suites** | **Solidity 0.8.26**

---

## Table of Contents

1. [Overview](#overview)
2. [Test Suite Breakdown](#test-suite-breakdown)
3. [Test Categories](#test-categories)
4. [Running Tests](#running-tests)
5. [Coverage Targets](#coverage-targets)
6. [Fuzz Testing](#fuzz-testing)

---

## Overview

The test suite validates all contracts, modules, and integrations across 12 test files:

| Test File | Tests | Focus Area |
|-----------|:-----:|------------|
| `FixerHook.t.sol` | ~8 | v1 hook: encoding, permissions, validation logic |
| `FixerHookV1_1.t.sol` | ~30 | v1.1 dynamic rewards: volume math, thresholds, per-pool config, fuzz |
| `FixerHookV1_2.t.sol` | ~25 | v1.2 tiered referrals: tier thresholds, multipliers, upgrade logic |
| `FixerRegistry.t.sol` | ~30 | v2 registry: init, hook auth, referral recording, cross-pool volume |
| `FixerRegistryUpgrade.t.sol` | ~25 | UUPS proxy: initialization, 48h timelock, state preservation, versioning |
| `FixerCredential.t.sol` | ~25 | Soulbound NFT: minting, transfer restrictions, SVG, refresh, ERC-5192 |
| `EmergencyModule.t.sol` | ~30 | Pause/resume states, DAO threshold, circuit breaker, access control |
| `ERC8004.t.sol` | ~50 | Agent registration, reputation caching, bonus computation, feedback |
| `X402.t.sol` | ~40 | EIP-3009 transferWithAuthorization, agent delegation, platform types |
| `XMTP.t.sol` | ~20 | enableXMTP, disableXMTP, endpoint updates, counter tracking, validation |
| `CoverageGap.t.sol` | ~35 | BPSMath, pool info, resumeRewards/Referrals, DAO threshold, fuzz |
| `Hardening.t.sol` | ~25 | MAX_SUPPLY cap, circuit breaker limits, daily ceiling, timelock, BPSMath |

**Test helper:** `test/helpers/IFixerRegistryFull.sol` — combined interface for calling Extension functions through the proxy's DELEGATECALL fallback.

**Total: 381 tests, 35 suites, 0 failures**

---

## Test Suite Breakdown

### FixerHook.t.sol — v1 Core Hook

Tests the original monolithic hook (BaseHook + ERC20):
- hookData encoding/decoding round-trip
- Hook permission configuration (only afterSwap = true)
- Referrer validation (zero address, self-referral)
- REWARD_AMOUNT constant verification
- Token metadata (name, symbol, decimals)

### FixerHookV1_1.t.sol — Dynamic Rewards

Tests volume-based reward calculation:
- `rewardRateBps` → reward math (10 BPS = 0.1% of volume)
- Min/max reward clamping (1–1,000 FIX per swap)
- Per-pool configuration (`PoolRewardConfig`)
- Volume threshold enforcement (`minSwapAmount`)
- Quote token index selection
- **Fuzz tests:** random volumes, edge values, overflow

### FixerHookV1_2.t.sol — Tier System

Tests referrer tier promotions and multipliers:
- Bronze→Silver→Gold→Platinum threshold qualification
- Volume + referral count requirements
- Multiplier application (1.0x→2.0x)
- Tier downgrade prevention (monotonic progression)
- Edge cases: exactly at threshold, just below

### FixerRegistry.t.sol — Central Registry

Tests the non-upgradeable v1 registry:
- Initialization parameters
- Hook authorization (register/deregister)
- `recordReferral()` full flow
- Cross-pool volume tracking
- Tier upgrades from recorded referrals
- Admin functions: setRewardRate, setMinSwapAmount

### FixerRegistryUpgrade.t.sol — UUPS Proxy

Tests upgrade mechanisms:
- Proxy initialization (5-phase initializer chain)
- State preservation across upgrades
- **48h timelock flow:** propose → wait → execute
- `cancelUpgrade()` by owner
- Direct `upgradeToAndCall()` rejection
- Version tracking (VERSION constant)
- `_authorizeUpgrade()` validation

### FixerCredential.t.sol — Soulbound NFT

Tests credential lifecycle:
- Minting (requires ≥1 referral)
- One-per-referrer enforcement
- **Soulbound transfer restriction:** transferFrom, safeTransferFrom, approve, setApprovalForAll all revert `TokenLocked()`
- On-chain SVG generation with tier-based colors
- `refresh()` updates metadata from registry
- `tokenURI()` returns valid base64-encoded JSON
- ERC-165 interface support (ERC-721, ERC-5192, ERC-4906)

### EmergencyModule.t.sol — Emergency Controls

Tests all safety mechanisms:
- Independent pause states (referrals, agents, rewards)
- Pause timestamps and duration tracking
- Security council instant pause
- **DAO governance threshold:** resume blocked after 7 days paused
- Circuit breaker trigger and auto-pause
- `pauseAll()` / `resumeAll()` atomicity
- `NothingPaused()` revert on unnecessary resume
- Access control (onlyOwner, onlySecurityCouncil)

### ERC8004.t.sol — Agent Infrastructure

Tests ERC-8004 integration (50+ tests):
- Agent registration via NFT ownership proof
- `FixerLib.validateAgent()` identity verification
- Reputation fetching and caching (1h TTL)
- Bonus BPS computation (0→500→1500→3000→5000)
- Stale cache degradation (50% reduction)
- `refreshAgentReputation()` force update
- `submitReferralFeedback()` to reputation registry
- Agent deregistration
- Rewards integration: tier × reputation multiplicative stacking
- `MAX_GROSS_REWARD` (5,000 FIX) enforcement

### X402.t.sol — Agent Payments

Tests x402/EIP-3009 integration:
- Agent registration across platforms (Human, OpenClaw, Moltbook, Custom)
- `transferWithAuthorization()` gasless FIX transfers
- EIP-712 signature validation
- Nonce management (single-use, rejection on replay)
- Time-bounded validity (validAfter/validBefore)
- Agent delegation: `delegateReferral()` / `revokeDelegation()`
- Platform type enumeration

### XMTP.t.sol — Communication Layer

Tests XMTP on-chain endpoint directory:
- `enableXMTP()` with public key hash and endpoint URI
- `disableXMTP()` clears state
- `updateXMTPEndpoint()` for URI changes
- `getXMTPEnabledCount()` counter accuracy
- Validation: non-agent blocked, zero key rejected, long URI rejected (>256 bytes)
- View functions: `isXMTPEnabled`, `getXMTPPublicKeyHash`, `getXMTPEndpoint`

### CoverageGap.t.sol — Gap Coverage

Fills residual coverage gaps:
- `resumeRewards()` and `resumeReferrals()` edge cases
- DAO governance threshold boundary conditions
- `NothingPaused()` revert scenarios
- `BPSMath` library: `applyBPS()`, `deductFee()`, `applyMultiplier()`
- Pool info registration and queries
- **Fuzz tests:** random BPS values, volume amounts, fee calculations

### Hardening.t.sol — Invariant Enforcement

Tests hard limits and safety constants:
- `MAX_SUPPLY` (1B FIX) enforcement in `_update()` override
- `MIN_CIRCUIT_BREAKER_LIMIT` (100K FIX) prevents disabling
- `MAX_CIRCUIT_BREAKER_LIMIT` (50M FIX) prevents excessive allowance
- `MAX_DAILY_MINT` (10M FIX) daily ceiling
- Upgrade timelock (48h) cannot be bypassed
- `BPSMath` integration with Solady `FixedPointMathLib.mulDiv`

---

## Test Categories

### Unit Tests
- Individual function behavior validation
- Input/output verification for pure/view functions
- Edge case handling (zero values, max values, boundary conditions)

### Integration Tests
- End-to-end referral flow: hook → registry → mint
- Proxy + Extension DELEGATECALL routing
- Agent registration → reputation → reward bonus

### Fuzz Tests
- Random volume values for reward calculation
- Random BPS values for fee computation
- Boundary testing with uint128/uint256 ranges
- Configuration: 256 runs, 15 invariant depth

### Access Control Tests
- `onlyOwner` modifier enforcement on admin functions
- `onlyAuthorizedHook` enforcement on `recordReferral()`
- `onlySecurityCouncil` enforcement on emergency functions
- Unauthorized caller rejection

---

## Running Tests

```bash
# Run all tests
forge test -vvv

# Run specific test file
forge test --match-path test/ERC8004.t.sol -vvv

# Run specific test function
forge test --match-test testAgentRegistration -vvv

# Run with gas report
forge test --gas-report

# Run with coverage
forge coverage

# Run fuzz tests with more runs
forge test --fuzz-runs 1024
```

Expected output:
```
Ran 35 test suites: 381 tests passed, 0 failed
```

---

## Coverage Targets

| Component | Target | Notes |
|-----------|:------:|-------|
| FixerHookV2 | >95% | All afterSwap paths covered |
| FixerRegistryUpgradeable | >90% | Complex state machine with many branches |
| FixerRegistryExtension | >85% | Agent functions + DELEGATECALL routing |
| FixerCredential | >95% | Simpler contract with clear boundaries |
| EmergencyModule | >95% | All pause/resume/circuit paths |
| FixerLib | >90% | External library — all public functions |
| BPSMath | >95% | Pure math — fully deterministic |

---

## Fuzz Testing

### Configuration (foundry.toml)

```toml
[fuzz]
runs = 256
max_test_rejects = 65536

[invariant]
runs = 256
depth = 15
fail_on_revert = false
```

### Key Fuzz Targets

| Test | Fuzzed Input | Property |
|------|-------------|----------|
| Reward calculation | volume (uint128) | Reward ∈ [minReward, MAX_GROSS_REWARD] |
| BPS application | bps (uint256) | Result ≤ input amount |
| Fee deduction | fee (uint64) | Net ≤ gross |
| Tier multiplier | volume (uint128) | Multiplier monotonically increases with tier |
| Circuit breaker | mint amount (uint128) | Sum never exceeds hourly limit without pause |

---

<p align="center">
  <em>Document Version: 3.0.0 | Last Updated: February 26, 2026</em>
</p>
