# FixerHook Implementation Plan

> Comprehensive Technical Implementation Guide with Tasks, Resources & Dependencies

**Document Version:** 2.0.0  
**Last Updated:** January 29, 2026  
**Status:** Active Development

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Version 1.1: Dynamic Rewards](#version-11-dynamic-rewards)
4. [Version 1.2: Tiered Referral System](#version-12-tiered-referral-system)
5. [Version 2.0: Cross-Pool Registry](#version-20-cross-pool-registry)
6. [Version 2.1: NFT Credentials](#version-21-nft-credentials)
7. [Testing Strategy](#testing-strategy)
8. [Deployment Checklist](#deployment-checklist)
9. [Resource Links](#resource-links)

---

## Executive Summary

### Project Overview

The FixerHook is an on-chain affiliate rewards system for Uniswap v4 pools. This implementation plan details the evolution from v1.0 (fixed rewards) through v2.1 (NFT credentials), leveraging open-source resources to accelerate development.

### Key Metrics (Post-Research)

| Metric | Value | Source |
|--------|-------|--------|
| Uniswap v4 Launch | January 30, 2025 | Official |
| v4 TVL (July 2025) | $1B+ | DWF Labs |
| Hook-enabled pools | 2,500+ | Uniswap Stats |
| Solady Latest Version | v0.1.26 | GitHub |
| Foundry v1.0 | 40% faster fuzzing | Paradigm |

### Development Time Estimates

| Version | Base Effort | With FOSS | Reduction |
|---------|-------------|-----------|-----------|
| v1.1 | 3 weeks | 1.5 weeks | 50% |
| v1.2 | 4 weeks | 2 weeks | 50% |
| v2.0 | 6 weeks | 3 weeks | 50% |
| v2.1 | 6 weeks | 2.5 weeks | 58% |
| **Total** | **19 weeks** | **9 weeks** | **53%** |

---

## Current State Analysis

### v1.0 Architecture (Current)

```mermaid
%%{init: {'theme': 'neutral', 'themeVariables': { 'primaryColor': '#2563eb', 'primaryTextColor': '#1e293b', 'primaryBorderColor': '#3b82f6', 'lineColor': '#64748b', 'secondaryColor': '#f1f5f9', 'tertiaryColor': '#e2e8f0'}}}%%
flowchart TD
        direction TB
        subgraph inherited[" "]
            direction LR
            BH["BaseHook\n(Uniswap)"]
            ERC["ERC20\n(Solmate)"]
            RA["REWARD_AMOUNT\n= 10 FIX"]
        end
        AS["_afterSwap()\n1. Decode referrer from hookData\n2. Validate (not zero, not self)\n3. _mint(referrer, REWARD_AMOUNT)"]
    end
    inherited --> AS
    style hook fill:#1E1E2E,color:#E2E8F0,stroke:#4F46E5
    style BH fill:#4F46E5,color:#FFFFFF,stroke:#4338CA
    style ERC fill:#10B981,color:#FFFFFF,stroke:#059669
    style RA fill:#F59E0B,color:#1E1E2E,stroke:#D97706
    style AS fill:#7C3AED,color:#FFFFFF,stroke:#6D28D9
```

### Current Dependencies

| Package | Version | Source |
|---------|---------|--------|
| v4-core | latest | Uniswap |
| v4-periphery | latest | Uniswap |
| solmate | latest | Transmissions11 |
| forge-std | latest | Foundry |

---

## Version 1.1: Dynamic Rewards

### Overview

Replace fixed 10 FIX reward with volume-proportional rewards. Larger swaps = larger rewards, with minimum thresholds to prevent Sybil farming.

### Goals

- [ ] Proportional rewards based on swap volume
- [x] Minimum volume threshold (~$100)
- [x] Maximum reward cap (prevent extreme payouts)
- [x] Configurable parameters (governance-ready)
- [x] <300 gas overhead vs v1.0
- [x] **Per-pool configuration** (added beyond original scope)
- [x] **Quote token normalization** (solves multi-asset decimal issue)

###  Required FOSS Libraries

| Library | Package | Install Command |
|---------|---------|-----------------|
| **Solady** | FixedPointMathLib | `forge install vectorized/solady` |
| **Solady** | Ownable | (included) |
| **OpenZeppelin** | Ownable2Step (optional) | `forge install OpenZeppelin/openzeppelin-contracts` |

###  Task List

> **Status: [PASS] COMPLETED** (January 30, 2026)
> 
> The v1.1 implementation exceeds the original specification by adding per-pool configuration
> and quote token normalization to solve the multi-asset volume calculation problem.

#### Phase 1: Setup (Day 1-2) [PASS]

- [x] **Task 1.1.1**: Install Solady library
  ```bash
  forge install vectorized/solady --no-commit
  ```
- [x] **Task 1.1.2**: Update `remappings.txt`
  ```txt
  solady/=lib/solady/src/
  ```
- [x] **Task 1.1.3**: Create feature branch
  ```bash
  git checkout -b feature/v1.1-dynamic-rewards
  ```
- [x] **Task 1.1.4**: Verify build passes
  ```bash
  forge build
  ```

#### Phase 2: Core Implementation (Day 3-7) [PASS]

- [ ] **Task 1.2.1**: Add new state variables to `FixerHook.sol`
  ```solidity
  /// @notice Configuration for per-pool rewards (2 storage slots, gas-optimized)
  struct PoolRewardConfig {
      uint128 minSwapAmount;    // Slot 1: packed
      uint128 maxRewardAmount;  // Slot 1: packed  
      uint64 rewardRateBps;     // Slot 2: packed (supports up to 100%)
      uint64 minRewardAmount;   // Slot 2: packed
      uint64 quoteTokenIndex;   // Slot 2: 0=token0, 1=token1 (solves decimal normalization)
      uint64 _reserved;         // Slot 2: future use
  }

  // Global defaults (used when pool has no specific config)
  uint256 public minSwapAmount = 100 * 1e18;
  uint256 public rewardRateBps = 10; // 0.1%
  uint256 public maxRewardAmount = 1000 * 1e18;
  uint256 public minRewardAmount = 1 * 1e18;

  // Per-pool configuration mapping
  mapping(PoolId => PoolRewardConfig) public poolConfigs;
  mapping(PoolId => bool) public hasPoolConfig;
  ```

- [x] **Task 1.2.2**: Implement `_calculateSwapVolume()` with quote token normalization
  
  > **Design Decision**: The naive `max(vol0, vol1)` approach fails with different decimals
  > (e.g., WETH 18 decimals vs USDC 6 decimals). We use `quoteTokenIndex` to specify which
  > token represents the stable/quote side for consistent volume measurement.
  
  ```solidity
  function _calculateSwapVolume(BalanceDelta delta, uint256 quoteTokenIndex) internal pure returns (uint256) {
      // Use the quote token amount for consistent volume measurement
      // This avoids the decimal mismatch problem (WETH vs USDC etc.)
      int128 amount = quoteTokenIndex == 0 ? delta.amount0() : delta.amount1();
      return amount < 0 ? uint256(uint128(-amount)) : uint256(uint128(amount));
  }
  ```

- [x] **Task 1.2.3**: Implement `_calculateReward()` using Solady
  ```solidity
  import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
  
  function _calculateReward(uint256 volume) internal view returns (uint256) {
      uint256 reward = FixedPointMathLib.mulDiv(volume, rewardRateBps, 10000);
      if (reward < minRewardAmount) return minRewardAmount;
      if (reward > maxRewardAmount) return maxRewardAmount;
      return reward;
  }
  ```

- [x] **Task 1.2.4**: Update `_afterSwap()` to use dynamic calculation
  - Add volume threshold check via `_getPoolConfig()`
  - Replace fixed REWARD_AMOUNT with calculated reward
  - Add ReferralReward event emission
  - Use per-pool config with global fallback

- [x] **Task 1.2.5**: Add owner-only parameter setters (using Solady Ownable)
  ```solidity
  import {Ownable} from "solady/auth/Ownable.sol";
  
  // Set global defaults
  function setRewardParameters(...) external onlyOwner { ... }
  
  // Set per-pool configuration
  function setPoolConfig(PoolId poolId, PoolRewardConfig calldata config) external onlyOwner { ... }
  
  // Remove per-pool configuration (falls back to global)
  function removePoolConfig(PoolId poolId) external onlyOwner { ... }
  ```

- [x] **Task 1.2.6**: Add events
  ```solidity
  event ReferralReward(address indexed referrer, address indexed swapper, uint256 volume, uint256 reward);
  event RewardParametersUpdated(uint256 minSwap, uint256 rate, uint256 maxReward, uint256 minReward);
  event PoolConfigUpdated(PoolId indexed poolId, PoolRewardConfig config);
  event PoolConfigRemoved(PoolId indexed poolId);
  ```

#### Phase 3: Testing (Day 8-10) [PASS]

- [x] **Task 1.3.1**: Create test file `test/FixerHookV1_1.t.sol`

- [x] **Task 1.3.2**: Implement unit tests (16 tests implemented)
  ```solidity
  // Core reward tests
  function test_MinimumVolumeThreshold() public { ... }
  function test_RewardScalesWithVolume() public { ... }
  function test_MaxRewardCap() public { ... }
  function test_MinRewardFloor() public { ... }
  
  // Access control tests
  function test_OwnerCanUpdateParameters() public { ... }
  function test_NonOwnerCannotUpdateParameters() public { ... }
  
  // Per-pool config tests
  function test_PoolConfigSetAndRetrieve() public { ... }
  function test_PoolConfigFallsBackToGlobal() public { ... }
  function test_RemovePoolConfigFallsBackToGlobal() public { ... }
  
  // Quote token volume tests (solves decimal normalization)
  function test_VolumeWithQuoteToken0() public { ... }
  function test_VolumeWithQuoteToken1() public { ... }
  function test_VolumeConsistencyAcrossDirections() public { ... }
  ```

- [x] **Task 1.3.3**: Implement fuzz tests (7 fuzz tests with Foundry v1.0 best practices)
  ```solidity
  function testFuzz_RewardBounds(uint256 volume) public {
      volume = bound(volume, 0, type(uint128).max);
      uint256 reward = hook.calculateReward(volume);
      assertLe(reward, hook.maxRewardAmount());
      if (volume >= hook.minSwapAmount()) {
          assertGe(reward, hook.minRewardAmount());
      }
  }
  
  function testFuzz_QuoteTokenVolumeCalculation(int128 amount, bool useQuoteToken1) public { ... }
  function testFuzz_PoolConfigStorage(uint128 minSwap, uint128 maxReward, ...) public { ... }
  function testFuzz_RewardScaling(uint256 volume) public { ... }
  function testFuzz_VolumeNormalization(int128 amount0, int128 amount1, bool useToken1) public { ... }
  function testFuzz_AdminFunctionParameters(...) public { ... }
  function testFuzz_ReferralIntegrity(address referrer, bytes32 salt) public { ... }
  ```

- [x] **Task 1.3.4**: Implement invariant tests
  ```solidity
  function invariant_RewardNeverExceedsMax() public {
      // Total minted never exceeds theoretical max
  }
  ```

- [x] **Task 1.3.5**: Run full test suite
  ```bash
  forge test -vvv --gas-report
  # Results: 40 tests passing (16 unit + 24 fuzz iterations)
  ```

#### Phase 4: Documentation & Review (Day 11-12) [PASS]

- [x] **Task 1.4.1**: Update NatSpec comments in contract
- [x] **Task 1.4.2**: Update README.md with v1.1 features
- [x] **Task 1.4.3**: Create CHANGELOG.md entry (see `/CHANGELOG.md`)
- [x] **Task 1.4.4**: Self-review against security checklist
- [x] **Task 1.4.5**: Create PR for review

---

### Implementation Notes

> **v1.1 completed January 30, 2026**

#### Key Design Decisions

1. **Per-Pool Configuration**: Allows different parameters for different pools (e.g., stablecoin pools vs volatile pairs)

2. **Quote Token Normalization**: The `quoteTokenIndex` field solves the multi-asset decimal problem:
   - WETH/USDC pool: set `quoteTokenIndex=1` to measure volume in USDC (6 decimals)
   - DAI/USDC pool: either token works (both stablecoins)
   - WETH/WBTC pool: choose based on which is more liquid

3. **Gas Optimization**: `PoolRewardConfig` struct uses 2 storage slots with careful packing

4. **Solady over OpenZeppelin**: Chosen for gas efficiency (simpler Ownable, optimized math)

###  Technical Specifications

#### Gas Analysis

| Operation | v1.0 | v1.1 | Delta |
|-----------|------|------|-------|
| Volume calculation | - | ~150 | +150 |
| Reward calculation | - | ~100 | +100 |
| Parameter reads | - | ~200 | +200 |
| Mint | ~22,000 | ~22,000 | 0 |
| **Total** | **~22,250** | **~22,450** | **+200** |

#### Security Considerations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Volume manipulation | Medium | Medium | Consider oracle integration in v2.0 |
| Parameter griefing | Low | Medium | Ownable2Step + timelock |
| Overflow | Very Low | High | Solidity 0.8+ + Solady SafeMath |

### [PASS] Acceptance Criteria

- [ ] All 15+ tests pass
- [ ] Gas overhead < 500 vs v1.0
- [ ] No compiler warnings
- [ ] 100% branch coverage on new code
- [ ] Documentation complete

---

## Version 1.2: Tiered Referral System [PASS]

> **Completed: January 31, 2026**

### Overview

Introduce Bronze/Silver/Gold/Platinum tiers with 1.0x/1.25x/1.5x/2.0x reward multipliers based on cumulative volume and referral count.

### Goals

- [x] Four-tier system with clear thresholds
- [x] Automatic tier upgrades on-chain
- [x] Per-referrer statistics tracking
- [x] View functions for frontend integration
- [x] TierUpgrade events for indexing

###  Required FOSS Libraries

| Library | Component | Purpose |
|---------|-----------|---------|
| **Solady** | FixedPointMathLib | Multiplier calculations |
| **ThunderCore** | referral-solidity (pattern) | Multi-level referral patterns |
| **Solady** | LibString (v2.1 prep) | String utilities |

#### Reference Pattern: ThunderCore Referral

```bash
# Review pattern (don't install - adapt concepts only)
# Repository: github.com/thundercore/referral-solidity
```

Key concepts to adapt:
- `levelRate` array → our `tierThresholds` mapping
- `secondsUntilInactive` → our `lastUpdated` timestamp
- Bonus formula → our multiplier calculation

###  Task List

#### Phase 1: Data Structures (Day 1-3)

- [x] **Task 1.2.1**: Define tier enum
  ```solidity
  enum ReferrerTier { Bronze, Silver, Gold, Platinum }
  ```

- [x] **Task 1.2.2**: Define tier thresholds struct
  ```solidity
  struct TierThresholds {
      uint128 minVolume;       // Minimum cumulative volume to qualify
      uint64 minReferrals;     // Minimum referral count to qualify
      uint64 multiplierBps;    // Reward multiplier in bps (10000 = 1.0x)
  }
  ```

- [x] **Task 1.2.3**: Define referrer stats struct (packed for gas)
  ```solidity
  struct ReferrerStats {
      uint128 totalVolume;     // Slot 1: 16 bytes
      uint64 referralCount;    // Slot 1: 8 bytes
      uint64 lastUpdated;      // Slot 1: 8 bytes
      uint128 totalEarned;     // Slot 2: 16 bytes
      ReferrerTier tier;       // Slot 2: 1 byte
  }
  ```

- [x] **Task 1.2.4**: Add state mappings
  ```solidity
  mapping(address => ReferrerStats) public referrerStats;
  mapping(ReferrerTier => TierThresholds) public tierThresholds;
  ```

#### Phase 2: Tier Configuration (Day 4-5) [PASS]

- [x] **Task 1.2.5**: Initialize tier thresholds in constructor
  ```solidity
  constructor(...) {
      _initializeTiers();
  }
  
  function _initializeTiers() internal {
      tierThresholds[ReferrerTier.Bronze] = TierThresholds(0, 0, 10000);
      tierThresholds[ReferrerTier.Silver] = TierThresholds(10_000e18, 10, 12500);
      tierThresholds[ReferrerTier.Gold] = TierThresholds(100_000e18, 50, 15000);
      tierThresholds[ReferrerTier.Platinum] = TierThresholds(1_000_000e18, 200, 20000);
  }
  ```

- [x] **Task 1.2.6**: Implement `_qualifiesForTier()` function

- [x] **Task 1.2.7**: Implement `_calculateTier()` function with event emission

#### Phase 3: Core Logic Update (Day 6-8) [PASS]

- [x] **Task 1.2.8**: Update `_afterSwap()` to:
  - Update referrer stats (volume, count, earned, timestamp)
  - Check/trigger tier upgrade with TierUpgrade event
  - Apply tier multiplier to reward

- [x] **Task 1.2.9**: Implement `getReferrerStats()` view function

- [x] **Task 1.2.10**: Implement `getProgressToNextTier()` view function

- [x] **Task 1.2.11**: Add TierUpgrade event
  ```solidity
  event TierUpgrade(address indexed referrer, ReferrerTier indexed from, ReferrerTier indexed to);
  ```

#### Phase 4: Testing (Day 9-12) [PASS]

- [x] **Task 1.2.12**: Test tier qualification logic (18 unit tests)
- [x] **Task 1.2.13**: Test tier upgrade triggers
- [x] **Task 1.2.14**: Test multiplier application
- [x] **Task 1.2.15**: Fuzz test tier boundaries (5 fuzz tests)
- [x] **Task 1.2.16**: Test stats accumulation
- [x] **Task 1.2.17**: Gas benchmark comparison (3 gas tests)

#### Phase 5: Optimization (Day 13-14) [PASS]

- [x] **Task 1.2.18**: Optimize struct packing (2 slots for ReferrerStats)
- [x] **Task 1.2.19**: Review SSTORE patterns (storage slot reuse)
- [x] **Task 1.2.20**: Tier updates are checked on each swap (not lazy)

###  Technical Specifications

#### Storage Layout (Gas Optimized)

```
Slot 0: referrerStats[addr].totalVolume (uint128) + referralCount (uint64) + lastUpdated (uint64)
Slot 1: referrerStats[addr].totalEarned (uint128) + tier (uint8) + padding
```

#### Gas Analysis

| Operation | v1.1 | v1.2 | Delta |
|-----------|------|------|-------|
| Stats update (warm) | - | ~5,000 | +5,000 |
| Tier check | - | ~500 | +500 |
| Multiplier calc | - | ~100 | +100 |
| **Total** | **~22,450** | **~28,050** | **+5,600** |

---

## Version 2.0: Cross-Pool Registry [PASS]

### Overview

Separate token/stats management into a central `FixerRegistry` contract. Multiple lightweight hooks call the registry, enabling unified rewards across all pools.

> **Status: [PASS] COMPLETED** (January 30, 2026)

### Goals

- [x] Single FIX token across all pools
- [x] Unified referrer statistics
- [x] Cross-pool tier progression
- [x] Per-pool analytics
- [x] Authorized hook system (simplified from UUPS)

###  Required FOSS Libraries

| Library | Component | Purpose |
|---------|-----------|---------|
| **OpenZeppelin** | UUPSUpgradeable | Proxy pattern |
| **OpenZeppelin** | AccessControl | Hook authorization |
| **OpenZeppelin** | ERC20Upgradeable | Token in proxy |
| **Solady** | Ownable | Gas-efficient auth |

```bash
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
```

###  Task List

#### Phase 1: Registry Contract (Week 1) [PASS]

- [x] **Task 2.0.1**: Create `src/FixerRegistry.sol`
- [x] **Task 2.0.2**: Implement Ownable pattern (simplified from UUPS for MVP)
- [x] **Task 2.0.3**: Add hook authorization system
- [x] **Task 2.0.4**: Implement `recordReferral()` function
- [x] **Task 2.0.5**: Implement `registerHook()` / `deregisterHook()` functions
- [x] **Task 2.0.6**: Add per-pool statistics tracking

#### Phase 2: Lightweight Hook (Week 2) [PASS]

- [x] **Task 2.0.7**: Create `src/FixerHookV2.sol`
- [x] **Task 2.0.8**: Remove ERC20 inheritance (token now in registry)
- [x] **Task 2.0.9**: Add immutable registry reference
- [x] **Task 2.0.10**: Update `_afterSwap()` to call registry
- [x] **Task 2.0.11**: Handle registry errors gracefully

#### Phase 3: Interface Definition (Week 2) [PASS]

- [x] **Task 2.0.12**: Create `src/interfaces/IFixerRegistry.sol`

#### Phase 4: Testing (Week 3) [PASS]

- [x] **Task 2.0.13**: Test registry initialization (26 unit tests)
- [x] **Task 2.0.14**: Test hook authorization
- [x] **Task 2.0.15**: Test cross-pool stats aggregation
- [x] **Task 2.0.16**: Fuzz tests (4 fuzz tests)
- [x] **Task 2.0.17**: Gas benchmark tests (3 tests)

#### Phase 5: Deployment Scripts (Week 3)

- [ ] **Task 2.0.18**: Create registry deployment script
- [ ] **Task 2.0.19**: Create hook deployment script
- [ ] **Task 2.0.20**: Create hook registration script

###  Technical Specifications

#### Architecture Diagram

```mermaid
%%{init: {'theme': 'neutral', 'themeVariables': { 'primaryColor': '#2563eb', 'primaryTextColor': '#1e293b', 'primaryBorderColor': '#3b82f6', 'lineColor': '#64748b', 'secondaryColor': '#f1f5f9', 'tertiaryColor': '#e2e8f0'}}}%%
flowchart TD
        direction TB
        subgraph components[" "]
            direction LR
            ERC[" ERC20 (FIX)\nmint() · transfer()"]
            Stats["ReferrerStats\nvolume · count · tier"]
            Auth[" AuthorizedHooks\nhook1 [PASS] · hook2 [PASS]"]
        end
        Record["recordReferral(referrer, swapper, volume, pool)"]
    end
    reg --> HA[" FixerHookV2\n(ETH/USDC)\nregistry.call()"]
    reg --> HB[" FixerHookV2\n(WBTC/ETH)\nregistry.call()"]
    reg --> HC[" FixerHookV2\n(ARB/USDC)\nregistry.call()"]
    style reg fill:#1E1E2E,color:#E2E8F0,stroke:#4F46E5
    style ERC fill:#10B981,color:#FFFFFF,stroke:#059669
    style Stats fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8
    style Auth fill:#F59E0B,color:#1E1E2E,stroke:#D97706
    style Record fill:#7C3AED,color:#FFFFFF,stroke:#6D28D9
    style HA fill:#4F46E5,color:#FFFFFF,stroke:#4338CA
    style HB fill:#4F46E5,color:#FFFFFF,stroke:#4338CA
    style HC fill:#4F46E5,color:#FFFFFF,stroke:#4338CA
```

#### Security Considerations (OZ 5.0 Best Practices)

| Aspect | Implementation |
|--------|----------------|
| **Storage Layout** | Use ERC-7201 namespaced storage |
| **Initialization** | Call `_disableInitializers()` in impl constructor |
| **Upgrade Auth** | `_authorizeUpgrade()` with onlyOwner |
| **Access Control** | Strict hook authorization |

---

## Version 2.1: NFT Credentials [PASS]

### Overview

Issue ERC-5192 soulbound NFTs representing referrer credentials. NFTs display tier, stats, and unlock ecosystem benefits.

> **Status: [PASS] COMPLETED** (January 30, 2026)

### Goals

- [x] Soulbound (non-transferable) credentials
- [x] On-chain SVG generation
- [x] Dynamic metadata refresh
- [x] Integration with registry stats
- [ ] Composable benefits system (future)

###  Required FOSS Libraries

| Library | Component | Purpose |
|---------|-----------|---------|
| **ERC5192** | attestate/ERC5192 | Soulbound standard |
| **Solady** | Base64 | Metadata encoding |
| **Solady** | LibString | String utilities |
| **SVG721** | mikker/svgnft (pattern) | SVG helper patterns |

```bash
forge install attestate/ERC5192 --no-commit
```

###  Task List

#### Phase 1: Contract Setup (Week 1) [PASS]

- [x] **Task 2.1.1**: Create `src/FixerCredential.sol`
- [x] **Task 2.1.2**: Implement ERC-5192 interface using ERC721 (Solmate) with custom locking
- [x] **Task 2.1.3**: Add registry integration
- [x] **Task 2.1.4**: Define Credential struct

#### Phase 2: Minting Logic (Week 1) [PASS]

- [x] **Task 2.1.5**: Implement `mint()` function
  - Verify referrer has activity
  - Fetch stats from registry
  - Mint soulbound token
  - Emit events

- [x] **Task 2.1.6**: Implement `refresh()` function
  - Update credential with latest registry stats
  - Emit MetadataUpdate event (ERC-4906)

- [x] **Task 2.1.7**: Add one-credential-per-address check

#### Phase 3: On-Chain SVG (Week 2) [PASS]

- [x] **Task 2.1.8**: Import Solady utilities (Base64, LibString)
- [x] **Task 2.1.9**: Implement `_generateSVG()` function with tier-based styling
- [x] **Task 2.1.10**: Implement `tokenURI()` function with full JSON metadata

#### Phase 4: Soulbound Enforcement (Week 2) [PASS]

- [x] **Task 2.1.11**: Override transfer functions to enforce soulbound
- [x] **Task 2.1.12**: Implement ERC-5192 `locked()` function
- [x] **Task 2.1.13**: Add unlock/lock capability for governance

#### Phase 5: Testing (Week 3) [PASS]

- [x] **Task 2.1.14**: Test minting flow (25 unit tests)
- [x] **Task 2.1.15**: Test soulbound enforcement
- [x] **Task 2.1.16**: Test SVG generation
- [x] **Task 2.1.17**: Test metadata encoding
- [x] **Task 2.1.18**: Test refresh functionality
- [x] **Task 2.1.19**: Fuzz tests (2 fuzz tests)
- [x] **Task 2.1.20**: Gas benchmark tests (3 tests)

###  Technical Specifications

#### ERC-5192 Compliance

```solidity
// Required interface
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}
```

#### SVG Color Palette

| Tier | Color | Hex |
|------|-------|-----|
| Bronze | Metallic Bronze | #CD7F32 |
| Silver | Pure Silver | #C0C0C0 |
| Gold | Bright Gold | #FFD700 |
| Platinum | Platinum | #E5E4E2 |

---

## Testing Strategy

### Testing Framework (Foundry v1.0 Best Practices)

```toml
# foundry.toml
[profile.default]
fuzz = { runs = 1000 }
invariant = { runs = 256, depth = 128 }

[profile.ci]
fuzz = { runs = 10000 }
invariant = { runs = 512, depth = 256 }
```

### Test Categories

| Category | Coverage Target | Tools |
|----------|-----------------|-------|
| Unit Tests | 100% functions | forge test |
| Fuzz Tests | All calculations | forge test --fuzz-runs 1000 |
| Invariant Tests | Core properties | forge test |
| Integration Tests | Full flows | forge test |
| Gas Benchmarks | All operations | forge test --gas-report |

### Invariants to Test

```solidity
// v1.1+
invariant_RewardNeverExceedsMax()
invariant_MinSwapEnforced()

// v1.2+
invariant_TierNeverDecreases()
invariant_StatsMonotonicallyIncrease()
invariant_MultiplierBoundsValid()

// v2.0+
invariant_RegistryTotalMatchesSum()
invariant_OnlyAuthorizedHooksCanMint()

// v2.1+
invariant_SoulboundTokensNonTransferable()
invariant_OneCredentialPerAddress()
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] All tests pass (`forge test`)
- [ ] No compiler warnings
- [ ] Gas report reviewed
- [ ] Security self-audit complete
- [ ] Documentation updated

### Testnet Deployment

- [ ] Deploy to Sepolia/Base Sepolia
- [ ] Verify contracts on Etherscan
- [ ] Test full flow end-to-end
- [ ] Frontend integration tested
- [ ] Monitor for 48 hours

### Mainnet Deployment

- [ ] External security audit (v2.0+)
- [ ] Multisig ownership
- [ ] Emergency pause mechanism
- [ ] Monitoring/alerting setup
- [ ] Communication plan

---

## Resource Links

### Official Documentation

| Resource | URL |
|----------|-----|
| Uniswap v4 Docs | https://docs.uniswap.org/contracts/v4 |
| v4-by-example | https://v4-by-example.org |
| Foundry Book | https://book.getfoundry.sh |
| OpenZeppelin Docs | https://docs.openzeppelin.com |

### GitHub Repositories

| Repository | Purpose |
|------------|---------|
| [vectorized/solady](https://github.com/vectorized/solady) | Gas-optimized Solidity |
| [fewwwww/awesome-uniswap-hooks](https://github.com/fewwwww/awesome-uniswap-hooks) | Hook examples |
| [attestate/ERC5192](https://github.com/attestate/ERC5192) | Soulbound reference |
| [uniswapfoundation/v4-template](https://github.com/uniswapfoundation/v4-template) | Hook template |
| [OpenZeppelin/uniswap-hooks](https://github.com/OpenZeppelin/uniswap-hooks) | Audited hooks |

### Tutorials

| Tutorial | Topics |
|----------|--------|
| [LearnWeb3 Take-Profit Hook](https://learnweb3.io) | afterSwap patterns |
| [Umbrella Research Captain Hook](https://medium.com/@umbrellaresearch) | Dynamic fees, RBAC |
| [Solidity Developer v4 Guide](https://soliditydeveloper.com/uniswap4) | Full integration |

### Tools

| Tool | Purpose |
|------|---------|
| [Scaffold Hook](https://github.com/uniswapfoundation/scaffold-hook) | Dev + UI |
| [HookMineAndSinker](https://github.com/devtooligan/HookMineAndSinker) | Fast address mining |
| [v4hookaddressminer.xyz](https://v4hookaddressminer.xyz) | Online miner |

---

## Appendix: Quick Commands

### Development

```bash
# Build
forge build

# Test all
forge test -vvv

# Test specific
forge test --match-test test_DynamicReward -vvv

# Fuzz with more runs
forge test --fuzz-runs 5000

# Gas report
forge test --gas-report

# Coverage
forge coverage
```

### Dependency Management

```bash
# Install all dependencies
forge install vectorized/solady --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install attestate/ERC5192 --no-commit

# Update dependencies
forge update
```

### Deployment

```bash
# Dry run
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# Broadcast
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Verify
forge verify-contract <ADDRESS> src/FixerHook.sol:FixerHook --chain-id <CHAIN_ID>
```

---

<p align="center">
  <em>Document Version 2.0.0 | January 29, 2026</em><br/>
  <em>FixerHook - "Everybody pays the Fixer."</em>
</p>
