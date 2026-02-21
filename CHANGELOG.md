# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

![System Architecture](docs/diagrams/drawio/system-architecture.png)

## [1.2.0] - 2026-01-31

### Added

#### Tiered Referral System
- **Four-tier system**: Bronze → Silver → Gold → Platinum with progressive rewards
- **Reward multipliers**: 1.0x (Bronze), 1.25x (Silver), 1.5x (Gold), 2.0x (Platinum)
- **Automatic tier upgrades**: Tiers upgrade automatically when thresholds are met
- **Per-referrer statistics tracking**: Volume, referral count, earnings, last activity

#### Tier Thresholds
| Tier | Volume Required | Referrals Required | Multiplier |
|------|-----------------|-------------------|------------|
| Bronze | 0 | 0 | 1.0x |
| Silver | 10,000 | 10 | 1.25x |
| Gold | 100,000 | 50 | 1.5x |
| Platinum | 1,000,000 | 200 | 2.0x |

#### New Types
- `ReferrerTier` enum: Bronze, Silver, Gold, Platinum
- `TierThresholds` struct: minVolume, minReferrals, multiplierBps
- `ReferrerStats` struct: totalVolume, referralCount, lastUpdated, totalEarned, tier

#### New Functions
- `getReferrerStats(address)` - Get referrer's statistics and tier
- `getProgressToNextTier(address)` - Get progress toward next tier (volume/referral %)
- `getTierMultiplier(address)` - Get referrer's current tier multiplier
- `getTierThresholds(ReferrerTier)` - Get thresholds for a specific tier
- `setTierThresholds(ReferrerTier, TierThresholds)` - Admin: update tier thresholds
- `_calculateTier(volume, referrals)` - Internal tier calculation
- `_qualifiesForTier(tier, volume, referrals)` - Internal qualification check

#### New Events
- `TierUpgrade(address referrer, ReferrerTier from, ReferrerTier to)` - Tier promotion
- `TierThresholdsUpdated(ReferrerTier tier, TierThresholds thresholds)` - Admin config
- `PoolConfigRemoved(PoolId poolId)` - Pool config removal

### Changed
- `_afterSwap()` now updates referrer stats and applies tier multiplier
- Rewards are multiplied by tier multiplier after base calculation
- Constructor now calls `_initializeTiers()` to set default thresholds

### Test Coverage
- **72 tests total** across 11 test contracts (26 new for v1.2)
- `FixerHookV1_2TierTest`: 18 unit tests for tier system
- `FixerHookV1_2FuzzTest`: 5 fuzz tests for tier calculations
- `FixerHookV1_2GasTest`: 3 gas benchmark tests

---

## [1.1.0] - 2026-01-30

### Added

#### Dynamic Rewards System
- **Volume-based rewards**: Replaced fixed 10 FIX reward with dynamic calculation based on swap volume
- **Configurable parameters**: `minSwapAmount`, `rewardRateBps`, `maxRewardAmount`, `minRewardAmount`
- **Per-pool configuration**: Each pool can have custom reward settings via `PoolRewardConfig` struct
- **Quote token volume calculation**: Fixed the volume calculation issue by using a designated quote token (typically stablecoin) for consistent volume measurement across different token pairs

#### New Functions
- `setPoolConfig(PoolId, PoolRewardConfig)` - Configure reward parameters for specific pools
- `removePoolConfig(PoolId)` - Remove per-pool config, falling back to global defaults
- `setRewardParameters(...)` - Update global reward parameters
- `calculateReward(uint256 volume)` - View function for reward calculation with global params
- `calculateRewardForPool(PoolId, uint256 volume)` - View function for pool-specific reward calculation
- `_getPoolConfig(PoolId)` - Internal function to get effective config (per-pool or global fallback)

#### Events
- `ReferralReward(address referrer, address swapper, PoolId poolId, uint256 volume, uint256 reward)` - Enhanced with poolId
- `RewardParametersUpdated(...)` - Emitted when global parameters change
- `PoolConfigured(PoolId, PoolRewardConfig)` - Emitted when per-pool config is set

### Changed
- Inherited `Ownable` from Solady for gas-efficient owner management
- Constructor now requires owner address parameter
- Volume calculation now uses quote token instead of max(abs(amount0), abs(amount1))

### Fixed
- **Volume Calculation Issue**: Previous implementation used `max(abs(amount0), abs(amount1))` which didn't account for token decimals. Now uses designated quote token for consistent volume measurement.
- **Global Parameters Issue**: Moved from global-only parameters to per-pool configuration support

### Security
- Added parameter validation in `setPoolConfig()` and `setRewardParameters()`
- Quote token index validated to be 0 or 1
- Reward rate validated to not exceed 100% (10000 bps)
- Min reward validated to not exceed max reward

### Test Coverage
- **46 tests total** across 8 test contracts
- New `FixerHookV1_1DecimalTest` contract with 6 tests:
  - `test_DecimalMismatch_DAI_USDC` - validates 18-dec vs 6-dec handling
  - `test_DecimalMismatch_WETH_USDC` - validates WETH/USDC volume calculation
  - `test_DecimalMismatch_WBTC_USDC` - validates 8-dec vs 6-dec handling
  - `test_StablecoinPool_EitherTokenWorks` - validates stablecoin pairs
  - `test_RewardScaling_DifferentDecimals` - validates reward calculation
  - `testFuzz_DecimalCombinations` - fuzz test for various decimal configs
- Volume calculation tests (quote token based)
- Per-pool configuration tests
- Admin function tests with access control
- Gas benchmark tests (<300 gas overhead)

## [1.0.0] - 2026-01-29

### Added
- Initial implementation of FixerHook
- Fixed reward of 10 FIX tokens per successful referral
- Self-referral prevention using `tx.origin`
- Zero address validation
- ERC20 FIX token embedded in hook contract
- `afterSwap` hook permission for minimal gas overhead

---

## Roadmap

### [2.0.0] - Planned  
- Cross-pool referral registry
- Unified FIX token across all pools
- Upgradeable registry architecture (UUPS)
