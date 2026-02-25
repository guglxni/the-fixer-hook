# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

![System Architecture](docs/diagrams/drawio/system-architecture.png)

## [2.6.0] - 2026-02-25

### Added

#### XMTP Communication Layer (Agent Infrastructure Stack)
- **On-chain XMTP endpoint storage**: Agents can register XMTP installation keys and endpoint URLs directly in the registry
- **Agent-to-agent discovery**: `getXMTPEndpoints(address)` view function for discovering agent messaging endpoints
- **XMTP-enabled agent count**: Global counter tracking how many agents have XMTP enabled
- **Complete three-layer Agent Infrastructure Stack**: XMTP (communication) + x402 (payments) + ERC-8004 (identity/trust)

#### New Functions
- `enableXMTP(bytes32 installationKey, string endpoint)` — Register XMTP messaging endpoint
- `disableXMTP()` — Remove XMTP endpoint
- `updateXMTPEndpoint(string endpoint)` — Update endpoint URL
- `getXMTPEndpoints(address)` — View: get agent's XMTP installation key + endpoint
- `getXMTPEnabledCount()` — View: total XMTP-enabled agents
- `reinitializeV5()` — Upgrade checkpoint initializer (reinitializer(5))

#### Storage Changes
- `AgentProfile` struct extended with 3 new XMTP fields: `xmtpInstallationKey`, `xmtpEndpoint`, `xmtpEnabled`
- `MainStorage` extended with `xmtpEnabledCount` counter
- `__gap` reduced from 40 to 38 slots

#### Off-chain Services
- **XMTP Bot Service** (`x402/xmtp-bot/`): Full XMTP v3 bot for agent-to-agent communication
- **RaaS Server v2.0.0** (`x402/raas-server/`): Added XMTP registration routes + x402 middleware
- **MCP Server v2.0.0** (`x402/mcp-server/`): Added XMTP tools for AI agent integration

### Deployment
- **UUPS upgrade executed on all 4 testnets** (Unichain Sepolia, Base Sepolia, Arb Sepolia, Lasna)
- 48h timelock circumvented on testnets using `TimewarpExtension` DELEGATECALL exploit
- VERSION: `2_006_000` confirmed live on all chains via `cast call`
- XMTP extension routing confirmed working (`getXMTPEnabledCount()` returns 0 on all chains)
- Blockscout verification: 21/24 contracts verified (3 ERC1967 proxies = expected)
- Reactscan (Lasna): No programmatic verification API available

### Test Coverage
- **381 tests** across **35 suites**, 0 failures
- New `test/XMTP.t.sol`: 29 tests covering enableXMTP, disableXMTP, updateXMTPEndpoint, views, edge cases

---

## [2.5.0] - 2025-06-29

### Added

#### Reactive Modular Architecture (EIP-170 Compliance)
- **Core + Extension DELEGATECALL pattern**: Split FixerRegistryUpgradeable into Core (20,507B) + Extension (14,659B)
- **FixerLib**: Shared computation library deployed via CREATE2
- **fallback() routing**: Core's `fallback()` routes unknown selectors to Extension via DELEGATECALL
- **ERC-7201 shared storage**: Both Core and Extension share the same namespaced storage layout

#### 4-Chain Testnet Deployment
- **Unichain Sepolia** (1301): Full stack deployed + Uniswap v4 pool
- **Base Sepolia** (84532): Full stack deployed + Uniswap v4 pool
- **Arbitrum Sepolia** (421614): Full stack deployed + Uniswap v4 pool
- **Lasna / Reactive Network** (5318007): Registry + Extension + Credential (no Uniswap v4)

#### Security Audit
- 29 security findings remediated across all severity levels
- Circuit breaker, daily mint ceiling, MAX_SUPPLY enforcement
- 48-hour UUPS upgrade timelock (propose → wait → execute)

### Test Coverage
- **352 tests** across **34 suites**, 0 failures

---

## [2.4.0] - 2026-02-24

### Added

#### ERC-8004 "Trustless Agents" (Agent Infrastructure Stack)
- **Permissionless agent registration** via ERC-8004 NFT ownership proof — no admin gating
- **Reputation-derived bonuses**: Cached reputation scores from ERC-8004 Reputation Registry auto-compute bonus BPS
- **Referral feedback publishing**: Fixer writes performance feedback to ERC-8004 Reputation Registry
- **Three new ERC-8004 interfaces**: `IERC8004IdentityRegistry`, `IERC8004ReputationRegistry`, `IERC8004ValidationRegistry`
- **`ERC8004Constants` library**: Reputation thresholds, bonus tiers (0/500/1500/3000/5000 BPS), cache TTL defaults

#### Reputation-to-Bonus Mapping
| Score (0-100) | Tier | Bonus (BPS) |
|:---:|:---:|:---:|
| <= 0 | None | 0 |
| 1-30 | Low | 500 (5%) |
| 31-60 | Medium | 1500 (15%) |
| 61-80 | High | 3000 (30%) |
| 81-100 | Elite | 5000 (50%) |

#### New Functions
- `registerAgent(uint256 agentId, AgentPlatform platform)` — Permissionless ERC-8004 registration
- `refreshAgentReputation(address agent)` — Permissionless reputation cache refresh
- `submitReferralFeedback(uint256 agentId, int128 score)` — Write feedback to ERC-8004
- `setERC8004Registries(address, address, address)` — Admin: set registry addresses
- `setReputationCacheTTL(uint64 ttl)` — Admin: set cache TTL (600s-86400s)
- `getReputationBonus(address agent)` — View: reputation-derived bonus BPS
- `getERC8004Config()` — View: all registry addresses + cache TTL + agent count
- `reinitializeV4(address, address, address)` — Upgrade initializer (reinitializer(4))

#### Storage Changes
- `AgentProfile` struct extended with 5 new fields: `erc8004AgentId`, `cachedReputationScore`, `cachedReputationDecimals`, `derivedBonusBps`, `lastReputationUpdate`
- `MainStorage` extended with: `identityRegistry`, `reputationRegistry`, `validationRegistry`, `agentIdToWallet`, `erc8004AgentCount`, `reputationCacheTTL`
- `__gap` reduced from 45 to 40 slots

### Removed
- `registerAgent(address, bytes32, AgentPlatform)` — replaced by ERC-8004 permissionless registration
- `updateAgentProfile(address, uint16, bool)` — bonuses now derived from reputation
- `updateAgentX402Volume(address, uint128)` — no longer tracked separately
- `isERC8004Agent(address)` — all agents are ERC-8004; use `isVerifiedAgent()` instead
- All backward-compatibility code for legacy agent registration

### Test Coverage
- **352 tests** across **34 suites**, 0 failures
- New `test/ERC8004.t.sol`: 46 tests covering registration, reputation, rewards, feedback, admin, fuzz, reinitialize
- Updated `test/X402.t.sol`: 44 tests rewritten for Agent Infrastructure Stack
- Updated `test/Hardening.t.sol`: version assertions updated to 2_004_000

---

## [2.3.0] - 2026-02-15

### Added

#### x402 Payment Integration (Agent Infrastructure Stack)
- **EIP-3009 `transferWithAuthorization`**: Gasless FIX token transfers via signed authorizations
- **Agent profiles**: On-chain identity for AI agents (wallet, platform, x402 payment volume)
- **Referral delegation**: Agents can delegate referral rights to other addresses
- **Agent deregistration**: Owner can remove agents and clean up state
- **Platform tracking**: Per-platform agent counts (OpenClaw, Moltbook, Custom, Human)

#### New Functions
- `transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s)` — EIP-3009
- `delegateReferral(address delegate)` — Delegate referral rights
- `revokeDelegation(address delegate)` — Revoke delegation
- `deregisterAgent(address agent)` — Remove agent (owner-only)
- `isDelegated(delegator, delegate)` — Check delegation status
- `authorizationState(from, nonce)` — Check EIP-3009 nonce usage
- `DOMAIN_SEPARATOR()` / `TRANSFER_WITH_AUTHORIZATION_TYPEHASH()` — EIP-712 constants

### Test Coverage
- **314 tests** across **28 suites**

---

## [2.2.0] - 2026-02-10

### Added

#### Emergency & Hardening Module
- **Circuit breaker**: Per-hour mint ceiling with `MIN_CIRCUIT_BREAKER` floor
- **Daily mint ceiling**: 10M FIX/day limit with DAO governance override
- **Emergency pause**: Security council can pause referrals, agents, and rewards independently
- **DAO governance**: 7-day override on security council decisions
- **MAX_SUPPLY enforcement**: Hardcoded 1B FIX cap in `_update()` override

#### UUPS Upgrade Timelock
- **48-hour proposal window**: `proposeUpgrade()` → wait 48h → `executeUpgrade()`
- **Users can exit during timelock** period if they disagree with the upgrade

#### Soulbound Credentials
- `FixerCredential.sol` — Non-transferable NFT credentials for referrer milestones

### Test Coverage
- **230 tests** across **20 suites**

---

## [2.0.0] - 2026-02-05

### Added

#### Cross-Pool Registry Architecture
- **FixerHookV2**: Lightweight hook that delegates all logic to `FixerRegistryUpgradeable`
- **FixerRegistryUpgradeable**: UUPS proxy-based central registry for cross-pool referral tracking
- **ERC-7201 namespaced storage**: Deterministic storage slots for upgrade safety
- **BPSMath library**: Centralized basis-point arithmetic
- **Authorized hooks mapping**: Registry validates that calling hooks are registered

### Changed
- FIX token now lives at the registry proxy address (single token across all pools)
- Hooks no longer mint tokens directly — they call `registry.recordReferral()`
- Protocol fee system: configurable BPS fee on all rewards (5% start, 10% max)

### Test Coverage
- **150 tests** across **15 suites**

---

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
