# Peer Review Checklist

> A structured guide for reviewing the FixerHook protocol codebase before external audit.

**Version:** 1.0  
**Applies to:** FixerRegistryUpgradeable v2.2.2, EmergencyModule, FixerHookV2, BPSMath

---

## How to Use This Checklist

1. Clone the repository and run `forge build && forge test`
2. Read `docs/SYSTEM_DESIGN.md` for architecture overview
3. Work through each section below, checking off items as you verify
4. Record any findings in the **Findings Log** at the bottom
5. Run static analysis: `slither src/ --config-file slither.config.json`
6. Run coverage: `forge coverage --no-match-test "Gas"`

---

## 1. Access Control

- [ ] **Owner-only functions** are protected by `onlyOwner` modifier
  - `setRewardParameters()`, `setProtocolFee()`, `setTierThresholds()`
  - `registerHook()`, `deregisterHook()`
  - `proposeUpgrade()`, `cancelUpgrade()`, `executeUpgrade()`
  - `distributeFees()`
- [ ] **Hook-only functions** check `onlyRegisteredHook` modifier
  - `recordReferral()` — only registered hooks can mint rewards
- [ ] **Emergency functions** use correct council/governance restrictions
  - `pauseReferrals()`, `pauseAgents()`, `pauseRewards()`, `pauseAll()` → `onlySecurityCouncil`
  - `resume*()` → security council within 7 days, otherwise DAO governance
  - `setCircuitBreaker()`, `setDailyMintCeiling()` → `onlySecurityCouncilOrGovernance`
- [ ] **No unprotected `selfdestruct` or `delegatecall`** in any contract
- [ ] **Initializer** runs atomically through proxy constructor (`ERC1967Proxy`)
- [ ] **`reinitialize()`** uses `reinitializer(2)` and cannot be replayed

---

## 2. Upgrade Safety (UUPS)

- [ ] **`_authorizeUpgrade()`** restricted to `onlyOwner`
- [ ] **48-hour timelock** enforced: `proposeUpgrade()` → wait → `executeUpgrade()`
- [ ] **Proposal cancellation** works and emits events
- [ ] **Storage layout** uses ERC-7201 namespaced storage (`FixerRegistryStorage`)
- [ ] **No storage variables** declared in inheriting contracts (all in storage lib)
- [ ] **Storage gap** is ≥50 slots (`uint256[50] private __gap`)
- [ ] **`UpgradeProposal` struct** includes `implementationAddress`, `proposedAt`, `active`
- [ ] **Version constant** (`VERSION`) increments on each upgrade

---

## 3. Token Economics & Minting

- [ ] **MAX_SUPPLY** = 1,000,000,000 × 10¹⁸ (1B FIX) — hardcoded constant
- [ ] **`_update()` override** reverts with `MaxSupplyExceeded` when supply + amount > MAX_SUPPLY
- [ ] **Circuit breaker**: per-hour mint tracking, revert when minting exceeds threshold
- [ ] **MIN_CIRCUIT_BREAKER** = 100,000 × 10¹⁸ — prevents DAO from disabling circuit breaker
- [ ] **Daily mint ceiling** = 10,000,000 × 10¹⁸ (10M FIX/day) with date-based tracking
- [ ] **Reward calculation**: `volume × rewardRateBps / 10000` then tier multiplier
- [ ] **Protocol fee**: deducted from gross reward, capped at `MAX_PROTOCOL_FEE_BPS`
- [ ] **BPSMath library**: `applyBPS()`, `deductFee()`, `applyMultiplier()` — verify no overflow
- [ ] **Accumulated fees** tracked separately, distributed by owner via `distributeFees()`
- [ ] **`accumulatedFees` overflow guard**: check addition doesn't exceed uint256 max

---

## 4. Referral System

- [ ] **Self-referral prevention**: `if (referrer == swapper) revert SelfReferral()`
- [ ] **Anti-gaming**: `tx.origin != referrer` check (documented as non-auth, gaming mitigation only)
- [ ] **Min swap amount**: configurable floor below which no reward is minted
- [ ] **Tier system**: Bronze → Silver → Gold → Platinum with volume + referral count thresholds
- [ ] **Tier thresholds**: configurable by owner, validated (Gold > Silver, Platinum > Gold)
- [ ] **Multipliers**: Bronze 1.0×, Silver 1.25×, Gold 1.5×, Platinum 2.0× (in BPS: 10000, 12500, 15000, 20000)
- [ ] **Stats tracking**: `totalVolume`, `totalRewards`, `referralCount`, `tier` per referrer
- [ ] **Pool tracking**: per-pool volume and referral counts via `poolId`

---

## 5. Emergency Module

- [ ] **Granular pausing**: referrals, agents, rewards can be paused independently
- [ ] **Per-state pause timestamps**: separate `pausedAt` for each subsystem
- [ ] **7-day DAO override**: security council cannot resume after 7 days without governance vote
- [ ] **`pauseAll()`/`resumeAll()`**: batch pause/resume with earliest-timestamp DAO check
- [ ] **Circuit breaker**: hourly mint tracking resets every hour (block.timestamp / 3600)
- [ ] **Already-paused checks**: double-pause reverts with descriptive errors
- [ ] **Not-paused checks**: resume-when-not-paused reverts correctly

---

## 6. Reentrancy & CEI

- [ ] **`nonReentrant` modifier** on `recordReferral()` and `distributeFees()`
- [ ] **Checks-Effects-Interactions** pattern: state updates before external calls
- [ ] **No external calls** in `recordReferral()` (pure internal state + mint)
- [ ] **`distributeFees()`**: accumulator zeroed before `_mint()`

---

## 7. Hook Integration (FixerHookV2)

- [ ] **`getHookPermissions()`**: only `afterSwap` enabled (minimal permissions)
- [ ] **No `beforeSwapReturnDelta`**: prevents NoOp rug-pull vector
- [ ] **`msg.sender` check**: hook functions only callable by PoolManager
- [ ] **Referrer extraction**: from `hookData` parameter, not `tx.origin`
- [ ] **Registry delegation**: hook delegates all state to `FixerRegistryUpgradeable`
- [ ] **Token type documentation**: NatSpec documents unsupported tokens

---

## 8. Math & Overflow Safety

- [ ] **No `unchecked` blocks** in reward/fee calculations
- [ ] **`FixedPointMathLib.mulDiv()`** used for large multiplications
- [ ] **BPS constants**: `BPS_DENOMINATOR = 10000`, used consistently
- [ ] **`setRewardParameters()` bounds**: `rewardRateBps ≤ MAX_REWARD_RATE_BPS`
- [ ] **Tier threshold validation**: monotonically increasing
- [ ] **No division by zero**: all divisors checked or guaranteed non-zero

---

## 9. Events & Observability

- [ ] **All state-changing functions** emit events
- [ ] **Upgrade events**: `UpgradeProposed`, `UpgradeCancelled`, `UpgradeExecuted`
- [ ] **Emergency events**: `ReferralsPaused`, `ReferralsResumed`, etc.
- [ ] **Referral events**: `ReferralRecorded` with full context (referrer, swapper, volume, reward, pool)
- [ ] **Indexed parameters**: addresses and pool IDs indexed for efficient filtering
- [ ] **No event emission before state change** (prevents misleading logs on revert)

---

## 10. Static Analysis & Testing

- [ ] **Slither**: run with `slither src/` — 0 high/medium findings
- [ ] **Line coverage**: >95% on production contracts (FixerRegistryUpgradeable, EmergencyModule, BPSMath)
- [ ] **Branch coverage**: >85% on production contracts
- [ ] **Fuzz tests**: all math functions fuzz-tested with 256+ runs
- [ ] **Invariant tests**: supply cap, fee conservation, tier monotonicity, BPS math
- [ ] **Edge cases**: zero amounts, max uint values, boundary conditions
- [ ] **Both swap directions**: zeroForOne = true AND false tested

---

## 11. Code Quality

- [ ] **NatSpec**: all public/external functions documented with `@notice`, `@param`, `@return`
- [ ] **Error messages**: custom errors used (not `require` strings) — gas efficient
- [ ] **Naming conventions**: consistent, descriptive, no abbreviations without context
- [ ] **Magic numbers**: replaced with named constants (e.g., `MAX_PROTOCOL_FEE_BPS`)
- [ ] **Dead code**: no unreachable functions or unused variables
- [ ] **Import minimality**: only needed interfaces/libraries imported

---

## 12. Deployment & Operations

- [ ] **Deployment script** (`Deploy.s.sol`) follows atomic init pattern
- [ ] **Constructor args**: PoolManager address validated
- [ ] **Proxy initialization**: cannot be front-run (atomic in constructor)
- [ ] **Address mining**: hook address has correct permission bits
- [ ] **Testnet deployment** documented in `docs/DEPLOYMENT.md`

---

## Findings Log

| # | Severity | Contract | Line(s) | Description | Status |
|---|----------|----------|---------|-------------|--------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

**Severity Levels:** Critical / High / Medium / Low / Informational

---

## Reviewer Sign-Off

| Reviewer | Date | Contracts Reviewed | Issues Found |
|----------|------|--------------------|--------------|
| | | | |
| | | | |

---

*Checklist based on the [Uniswap v4 Hook Security Framework](https://docs.uniswap.org/contracts/v4/security), OpenZeppelin security guidelines, and project-specific requirements.*
