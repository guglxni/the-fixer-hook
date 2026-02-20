# FOSS Resources & Libraries for Future Enhancements

> Open Source Libraries, Tools, and References for FixerHook Development

---

## Table of Contents

1. [Overview](#overview)
2. [Core Solidity Libraries](#core-solidity-libraries)
3. [Uniswap v4 Specific Resources](#uniswap-v4-specific-resources)
4. [v1.1 Dynamic Rewards Resources](#v11-dynamic-rewards-resources)
5. [v1.2 Tiered System Resources](#v12-tiered-system-resources)
6. [v2.0 Registry Architecture Resources](#v20-registry-architecture-resources)
7. [v2.1 NFT Credentials Resources](#v21-nft-credentials-resources)
8. [Development Tools](#development-tools)
9. [Integration Matrix](#integration-matrix)

---

## Overview

This document catalogs Free and Open Source Software (FOSS) repositories and resources that can accelerate development of future FixerHook enhancements. By leveraging battle-tested libraries, we can:

- **Reduce development time** by 40-60%
- **Improve security** through audited code
- **Maintain consistency** with ecosystem standards
- **Focus on business logic** rather than infrastructure

> 📚 **See Also:** [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) for step-by-step task lists combining these resources into actionable development phases.

---

## Core Solidity Libraries

### Gas-Optimized Foundations

| Library | Repository | License | Use Case |
|---------|------------|---------|----------|
| **Solady** | [vectorized/solady](https://github.com/vectorized/solady) | MIT | Gas-optimized ERC20, ERC721, utilities |
| **Solmate** | [transmissions11/solmate](https://github.com/transmissions11/solmate) | MIT | Gas-efficient tokens (currently used) |
| **OpenZeppelin** | [OpenZeppelin/openzeppelin-contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | MIT | Security-audited contracts |

#### Solady (Recommended for New Features)

```bash
forge install vectorized/solady
```

**Key Components for FixerHook:**

| Component | File | Gas Savings | Use Case |
|-----------|------|-------------|----------|
| `ERC20` | `src/tokens/ERC20.sol` | ~30% vs OZ | FIX token upgrade |
| `ERC721` | `src/tokens/ERC721.sol` | ~25% vs OZ | NFT credentials |
| `LibString` | `src/utils/LibString.sol` | N/A | On-chain SVG |
| `Base64` | `src/utils/Base64.sol` | N/A | Metadata encoding |
| `FixedPointMathLib` | `src/utils/FixedPointMathLib.sol` | N/A | Reward calculations |
| `Ownable` | `src/auth/Ownable.sol` | ~15% vs OZ | Admin functions |

**Example Integration:**

```solidity
import {ERC20} from "solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract FixerHookV2 is BaseHook, ERC20 {
    using FixedPointMathLib for uint256;
    
    function _calculateReward(uint256 volume) internal view returns (uint256) {
        // Use mulDiv for precise calculations without overflow
        return volume.mulDiv(rewardRateBps, 10000);
    }
}
```

#### OpenZeppelin Contracts

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

**Key Components:**

| Component | Use Case | Relevant Version |
|-----------|----------|------------------|
| `AccessControl` | Role-based permissions for v2.0 | v5.x |
| `Ownable2Step` | Secure ownership transfer | v5.x |
| `ReentrancyGuard` | Cross-contract safety | v5.x |
| `Pausable` | Emergency pause functionality | v5.x |

---

## Uniswap v4 Specific Resources

### Official Repositories

| Repository | Description | Stars |
|------------|-------------|-------|
| [Uniswap/v4-core](https://github.com/Uniswap/v4-core) | Core protocol contracts | 2.1k+ |
| [Uniswap/v4-periphery](https://github.com/Uniswap/v4-periphery) | Routers, hook examples | 500+ |
| [uniswapfoundation/v4-template](https://github.com/uniswapfoundation/v4-template) | Official hook template | 300+ |

### Community Resources

#### Awesome Uniswap Hooks

**Repository:** [fewwwww/awesome-uniswap-hooks](https://github.com/fewwwww/awesome-uniswap-hooks)

A curated list of 100+ hook examples, tools, and tutorials. Key relevant examples:

| Hook | Repository | Relevance to FixerHook |
|------|------------|------------------------|
| **UniDerp** | Production | Fee distribution to referrers (exact use case!) |
| **Volatility Fee Hook** | Community | Dynamic fee calculation patterns |
| **Stop Loss Order** | [saucepoint/v4-stoploss](https://github.com/saucepoint/v4-stoploss) | Complex afterSwap logic |
| **LP Fee Rebate** | Community | Reward distribution patterns |
| **veLP (Vote Escrow)** | [kadenzipfel/veLP](https://github.com/kadenzipfel/veLP) | Tiered staking patterns |

#### OpenZeppelin Uniswap Hooks Library

**Repository:** [OpenZeppelin/uniswap-hooks](https://github.com/OpenZeppelin/uniswap-hooks)

Production-ready, security-audited hook components:

```bash
forge install OpenZeppelin/uniswap-hooks
```

**Available Modules:**
- Base hook implementations
- Access control for hooks
- Reentrancy guards for hooks
- Common hook patterns

### v4-by-Example

**Website:** [v4-by-example.org](https://www.v4-by-example.org/)

Interactive examples for:
- Dynamic fee implementation
- Hook data encoding/decoding
- Delta modifications
- Pool state access

---

## v1.1 Dynamic Rewards Resources

### Volume Calculation

The FixerHook needs to calculate swap volumes from `BalanceDelta`. Reference implementations:

#### From Uniswap v4-core

```solidity
// BalanceDelta is a packed int256
// amount0 is in the upper 128 bits, amount1 in the lower 128 bits

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

function getSwapVolume(BalanceDelta delta) internal pure returns (uint256) {
    int128 amount0 = delta.amount0();
    int128 amount1 = delta.amount1();
    
    // Convert to absolute values
    uint256 abs0 = amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0));
    uint256 abs1 = amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1));
    
    return abs0 > abs1 ? abs0 : abs1;
}
```

### Price Oracle Integration

For USD-denominated volume thresholds:

| Oracle | Repository | Use Case |
|--------|------------|----------|
| **Chainlink** | [smartcontractkit/chainlink](https://github.com/smartcontractkit/chainlink) | External price feeds |
| **Uniswap TWAP** | Built-in v4-core | On-chain price averages |

#### Chainlink Integration Example

```solidity
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract FixerHookWithOracle {
    AggregatorV3Interface internal priceFeed;
    
    function getUSDValue(uint256 tokenAmount, address token) internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (tokenAmount * uint256(price)) / 1e8;
    }
}
```

### Dynamic Fee Hook References

| Repository | Description |
|------------|-------------|
| [naddison36/uniswap-v4-hooks](https://github.com/naddison36/uniswap-v4-hooks) | DynamicFeeHook with getFee() |
| [umbrellaresearch/uni-v4-hooks-tutorial](https://github.com/umbrellaresearch/uni-v4-hooks-tutorial) | Volatility-based fee adjustment |

---

## v1.2 Tiered System Resources

### Tier/Level System Patterns

#### ThunderCore Referral Solidity

**Repository:** [thundercore/referral-solidity](https://github.com/thundercore/referral-solidity)

Multi-level referral system with:
- Up to 3 referral levels
- Configurable level rates
- Active/inactive referrer tracking
- Bonus formula calculations

```bash
npm install @thundercore/referral-solidity
```

**Key Concepts to Adapt:**

```solidity
// From ThunderCore - adapt for tiers
struct ReferralConfig {
    uint256 decimals;           // Precision
    uint256 referralBonus;      // Base bonus rate
    uint256 secondsUntilInactive; // Activity tracking
    bool onlyRewardActiveReferrers;
    uint256[] levelRate;        // [6000, 3000, 1000] = 60%, 30%, 10%
}
```

#### Staking Tier Patterns

**Reference Implementations:**

| Repository | Pattern |
|------------|---------|
| [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix) | O(1) reward calculation |
| [Speedrun Ethereum Staking](https://speedrunethereum.com) | Duration-based multipliers |

**Lazy Reward Calculation Pattern (Recommended):**

```solidity
// Gas-efficient tier tracking
contract TieredRewards {
    struct UserInfo {
        uint256 totalVolume;
        uint256 referralCount;
        uint256 rewardDebt;
        uint8 tier;
    }
    
    uint256 public accRewardPerVolume; // Global accumulator
    
    function _updateRewards(address user, uint256 volume) internal {
        UserInfo storage info = userInfo[user];
        
        // Claim pending rewards first
        uint256 pending = (info.totalVolume * accRewardPerVolume) - info.rewardDebt;
        if (pending > 0) {
            _mint(user, pending);
        }
        
        // Update user state
        info.totalVolume += volume;
        info.referralCount += 1;
        info.rewardDebt = info.totalVolume * accRewardPerVolume;
        
        // Check tier upgrade
        _updateTier(user);
    }
}
```

### Union Referral System

**Repository:** [unioncredit/union-referral](https://github.com/unioncredit/union-referral)

Features:
- Access control integration
- Referral tracking
- Member registration

---

## v2.0 Registry Architecture Resources

### Upgradeable Proxy Patterns

For the central registry, use upgradeable patterns:

| Pattern | Repository | Recommendation |
|---------|------------|----------------|
| **UUPS Proxy** | OpenZeppelin | [PASS] Recommended (gas efficient) |
| **Transparent Proxy** | OpenZeppelin | Good for admin separation |
| **Beacon Proxy** | OpenZeppelin | Multiple hooks, single upgrade |

#### UUPS Implementation

```bash
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
```

```solidity
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract FixerRegistry is Initializable, UUPSUpgradeable, ERC20Upgradeable {
    
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __UUPSUpgradeable_init();
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

### Registry Pattern References

| Project | Pattern | Repository |
|---------|---------|------------|
| **ENS** | Name registry | [ensdomains/ens-contracts](https://github.com/ensdomains/ens-contracts) |
| **Lens Protocol** | Profile registry | [lens-protocol/core](https://github.com/lens-protocol/core) |
| **Safe (Gnosis)** | Module registry | [safe-global/safe-contracts](https://github.com/safe-global/safe-contracts) |

### Cross-Contract Communication

For hooks calling the registry:

```solidity
interface IFixerRegistry {
    function recordReferral(
        address referrer,
        address swapper,
        uint256 volume,
        bytes32 poolId
    ) external returns (uint256 reward);
    
    function getReferrerStats(address referrer) external view returns (
        uint256 totalVolume,
        uint256 referralCount,
        uint256 totalEarned,
        uint8 tier
    );
}

contract FixerHookV2 is BaseHook {
    IFixerRegistry public immutable registry;
    
    function _afterSwap(...) internal override returns (bytes4, int128) {
        // Delegate to registry
        uint256 reward = registry.recordReferral(referrer, tx.origin, volume, poolId);
        emit ReferralRecorded(referrer, reward);
        return (this.afterSwap.selector, 0);
    }
}
```

---

## v2.1 NFT Credentials Resources

### Soulbound Token Standards

#### ERC-5192 Reference Implementation

**Repository:** [attestate/ERC5192](https://github.com/attestate/ERC5192)

```bash
forge install attestate/ERC5192
# or
npm install erc5192
```

**Usage:**

```solidity
import {ERC5192} from "ERC5192/ERC5192.sol";

contract FixerCredential is ERC5192 {
    constructor() ERC5192("Fixer Credential", "FIXCRED", true) {} // true = locked
    
    function safeMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
        if (isLocked) emit Locked(tokenId);
    }
}
```

#### Alternative: Custom Implementation

For more control, extend Solady's ERC721:

```solidity
import {ERC721} from "solady/tokens/ERC721.sol";

contract SoulboundCredential is ERC721 {
    mapping(uint256 => bool) public locked;
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {
        if (from != address(0) && locked[tokenId]) {
            revert TokenLocked();
        }
    }
}
```

### On-Chain SVG Generation

#### SVG721 Helper Library

**Repository:** [mikker/svgnft](https://github.com/mikker/svgnft)

```bash
npm install svgnft
# or
yarn add svgnft
```

**Features:**
- Simplified on-chain SVG generation
- Base64 encoding helpers
- tokenURI override patterns

**Example:**

```solidity
import {SVG721} from "svgnft/SVG721.sol";

contract FixerCredentialNFT is SVG721 {
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return _buildTokenURI(tokenId, _generateSVG(tokenId));
    }
    
    function _generateSVG(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">',
            '<rect fill="#1a1a2e" width="400" height="400"/>',
            '<text x="200" y="200" text-anchor="middle" fill="gold">',
            _getTierName(tokenId),
            '</text>',
            '</svg>'
        ));
    }
}
```

#### Solady Base64 & LibString

For manual SVG generation with maximum gas efficiency:

```solidity
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

contract OnChainMetadata {
    using LibString for uint256;
    
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        string memory svg = _generateSVG(tokenId);
        string memory json = string(abi.encodePacked(
            '{"name":"Fixer #', tokenId.toString(), '",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
        ));
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }
}
```

### NFT Metadata Standards

| Standard | Use Case | Reference |
|----------|----------|-----------|
| ERC-721 Metadata | Basic NFT metadata | OpenZeppelin |
| ERC-4906 | Metadata update events | [EIP-4906](https://eips.ethereum.org/EIPS/eip-4906) |
| ERC-5192 | Soulbound locking | attestate/ERC5192 |

---

## Development Tools

### Testing & Development

| Tool | Repository | Purpose |
|------|------------|---------|
| **Foundry** | [foundry-rs/foundry](https://github.com/foundry-rs/foundry) | Testing framework |
| **forge-std** | [foundry-rs/forge-std](https://github.com/foundry-rs/forge-std) | Testing utilities |
| **Scaffold Hook** | [uniswapfoundation/scaffold-hook](https://github.com/uniswapfoundation/scaffold-hook) | Hook development with UI |

### Hook-Specific Tools

| Tool | Repository | Purpose |
|------|------------|---------|
| **HookMineAndSinker** | [devtooligan/HookMineAndSinker](https://github.com/devtooligan/HookMineAndSinker) | Fast address mining |
| **Hookmate** | [saucepoint/hookmate](https://github.com/saucepoint/hookmate) | Hook utilities (extsload, fees) |
| **Hook Test Framework** | [khegeman/uniswapv4-hook-test-framework](https://github.com/khegeman/uniswapv4-hook-test-framework) | Fuzz testing for hooks |

### Address Mining (Improved)

The current `HookMiner.sol` can be replaced with faster alternatives:

```bash
# Use online tool for quick mining
# https://v4hookaddressminer.xyz/

# Or use HookMineAndSinker for CLI
git clone https://github.com/devtooligan/HookMineAndSinker
cd HookMineAndSinker
cargo run -- --flags 0x80 --deployer YOUR_ADDRESS
```

---

## Integration Matrix

### Version → Library Mapping

| Version | Required Libraries | Optional Libraries |
|---------|-------------------|-------------------|
| **v1.1** | Solady (FixedPointMath), forge-std | Chainlink (price feeds) |
| **v1.2** | v1.1 + Solady (Ownable) | ThunderCore patterns |
| **v2.0** | v1.2 + OZ Upgradeable, AccessControl | ENS patterns |
| **v2.1** | v2.0 + ERC5192, Solady (Base64, LibString) | svgnft |

### Installation Commands

```bash
# Core libraries (all versions)
forge install transmissions11/solmate --no-commit
forge install vectorized/solady --no-commit
forge install foundry-rs/forge-std --no-commit

# v1.2+ (Access Control)
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# v2.0+ (Upgradeable)
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

# v2.1 (Soulbound NFTs)
forge install attestate/ERC5192 --no-commit
```

### Recommended remappings.txt

```txt
# Core
v4-core/=lib/v4-core/src/
v4-periphery/=lib/v4-periphery/
solmate/=lib/solmate/
forge-std/=lib/forge-std/src/

# Enhanced
solady/=lib/solady/src/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/

# NFT (v2.1)
ERC5192/=lib/ERC5192/src/
```

---

## Quick Reference: Copy-Paste Code Snippets

### Dynamic Reward Calculation (v1.1)

```solidity
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

function calculateReward(uint256 volume, uint256 rateBps, uint256 min, uint256 max) 
    internal pure returns (uint256) 
{
    uint256 reward = FixedPointMathLib.mulDiv(volume, rateBps, 10000);
    if (reward < min) return min;
    if (reward > max) return max;
    return reward;
}
```

### Tier Upgrade Check (v1.2)

```solidity
function checkTierUpgrade(uint256 volume, uint256 count) internal pure returns (uint8) {
    if (volume >= 1_000_000e18 && count >= 200) return 3; // Platinum
    if (volume >= 100_000e18 && count >= 50) return 2;   // Gold
    if (volume >= 10_000e18 && count >= 10) return 1;    // Silver
    return 0; // Bronze
}
```

### Registry Hook Call (v2.0)

```solidity
try registry.recordReferral(referrer, tx.origin, volume, poolId) returns (uint256 reward) {
    emit ReferralRecorded(referrer, reward);
} catch {
    // Fallback: local reward if registry fails
    _mint(referrer, fallbackReward);
}
```

### On-Chain SVG Template (v2.1)

```solidity
function _tierSVG(uint8 tier) internal pure returns (string memory) {
    string[4] memory colors = ["#CD7F32", "#C0C0C0", "#FFD700", "#E5E4E2"];
    string[4] memory names = ["BRONZE", "SILVER", "GOLD", "PLATINUM"];
    
    return string(abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">',
        '<rect fill="#0a0a0f" width="400" height="400"/>',
        '<circle cx="200" cy="150" r="80" fill="', colors[tier], '"/>',
        '<text x="200" y="280" font-size="32" fill="white" text-anchor="middle">',
        names[tier], '</text></svg>'
    ));
}
```

---

## Tutorials & Learning Resources

| Resource | URL | Topics |
|----------|-----|--------|
| v4 by Example | [v4-by-example.org](https://www.v4-by-example.org/) | All hook concepts |
| LearnWeb3 Hook Tutorial | [learnweb3.io](https://learnweb3.io) | Take-profit orders |
| Umbrella Research | [Medium](https://medium.com/@umbrellaresearch) | Dynamic fees, RBAC |
| OpenZeppelin Hook Guide | [Twitter/X Thread](https://x.com/OpenZeppelin) | Security considerations |

---

## Summary

By leveraging these FOSS resources, the FixerHook enhancement roadmap can be accelerated significantly:

| Version | Time Savings | Key Libraries |
|---------|--------------|---------------|
| v1.1 | ~40% | Solady FixedPointMath |
| v1.2 | ~50% | ThunderCore patterns, Solady Ownable |
| v2.0 | ~60% | OZ Upgradeable, Registry patterns |
| v2.1 | ~70% | ERC5192, svgnft, Solady Base64 |

**Total estimated development time reduction: 50-60%**

---

<p align="center">
  <em>Document Version: 1.0.0 | Last Updated: January 2026</em>
</p>
