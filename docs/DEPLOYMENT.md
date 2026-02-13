# Deployment Guide

> Deploy the FixerHook Protocol — Hook, Upgradeable Registry, and Proxy Infrastructure

**Last Updated:** February 6, 2026  
**Covers:** FixerHook v1 (hook mining), FixerRegistryUpgradeable v2.2 (UUPS proxy), Upgrade process

---

## Overview

Uniswap v4 hooks require deployment to addresses with specific bits set based on enabled permissions. This guide covers the address mining and deployment process.

```mermaid
flowchart LR
    Mine["⛏️ Hook Mining\nCREATE2 address search"] --> Deploy["🚀 Deploy Contracts\nImpl + Proxy + Hook"]
    Deploy --> Verify["✅ Verify\nBlock explorer"]
    Verify --> Config["⚙️ Configure\nRegister hooks, set params"]
    Config --> Test["🧪 Post-Deploy Check\nSmoke tests"]

    style Mine fill:#F59E0B,color:#1E1E2E,stroke:#D97706
    style Deploy fill:#4F46E5,color:#FFFFFF,stroke:#4338CA
    style Verify fill:#10B981,color:#FFFFFF,stroke:#059669
    style Config fill:#7C3AED,color:#FFFFFF,stroke:#6D28D9
    style Test fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8
```

---

## Address Requirements

### Permission Bits

| Permission | Bit Position | Flag Value |
|------------|--------------|------------|
| afterSwap | 7 | `0x80` |

For `afterSwap` only, the hook address must have bit 7 set.

**Example valid addresses:**
- `0x...80` 
- `0x...81` (multiple flags)

---

## Hook Mining

### Using CREATE2

The `HookMiner` library finds valid addresses by iterating through salts:

```solidity
library HookMiner {
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, initCodeHash);
            
            if (uint160(hookAddress) & flags == flags) {
                return (hookAddress, salt);
            }
        }
        revert("No valid address found");
    }
}
```

---

## Deployment Script

```solidity
// script/Deploy.s.sol
contract DeployReferralHook is Script {
    function run() external {
        // Load config
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Find valid address
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            vm.addr(deployerPrivateKey),
            flags,
            type(ReferralHook).creationCode,
            constructorArgs
        );
        
        console.log("Deploying to:", hookAddress);
        
        // Deploy
        vm.startBroadcast(deployerPrivateKey);
        
        ReferralHook hook = new ReferralHook{salt: salt}(
            IPoolManager(poolManager)
        );
        
        require(address(hook) == hookAddress, "Address mismatch");
        
        vm.stopBroadcast();
    }
}
```

---

## Network Configuration

### Testnets

| Network | PoolManager | RPC |
|---------|-------------|-----|
| Sepolia | `0x...` | `https://sepolia.infura.io/v3/KEY` |
| Base Sepolia | `0x...` | `https://sepolia.base.org` |
| Arbitrum Sepolia | `0x...` | `https://sepolia-rollup.arbitrum.io/rpc` |

### Mainnet

| Network | PoolManager | Notes |
|---------|-------------|-------|
| Ethereum | `0x...` | High gas costs |
| Base | `0x...` | Recommended for low gas |
| Arbitrum | `0x...` | Recommended for low gas |

> **Note:** Check Uniswap documentation for latest PoolManager addresses.

---

## Environment Setup

Create `.env` file:

```bash
PRIVATE_KEY=0x...
POOL_MANAGER=0x...
RPC_URL=https://...
ETHERSCAN_API_KEY=...
```

---

## Deployment Commands

```bash
# Set environment variables
source .env

# Dry run (simulation)
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# Deploy to network
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# Verify separately if needed
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/ReferralHook.sol:ReferralHook \
  --chain-id <CHAIN_ID> \
  --constructor-args $(cast abi-encode "constructor(address)" $POOL_MANAGER)
```

---

## Post-Deployment Verification

### 1. Verify Permissions

```bash
cast call <HOOK_ADDRESS> "getHookPermissions()" --rpc-url $RPC_URL
```

### 2. Verify Token Metadata

```bash
cast call <HOOK_ADDRESS> "name()" --rpc-url $RPC_URL
cast call <HOOK_ADDRESS> "symbol()" --rpc-url $RPC_URL
cast call <HOOK_ADDRESS> "decimals()" --rpc-url $RPC_URL
```

### 3. Verify Reward Amount

```bash
cast call <HOOK_ADDRESS> "REWARD_AMOUNT()" --rpc-url $RPC_URL
```

---

## Gas Considerations

| Network | Referral Swap Gas | Cost (est.) |
|---------|-------------------|-------------|
| Ethereum | ~172k | $5-50 |
| Base | ~172k | $0.01-0.05 |
| Arbitrum | ~172k | $0.05-0.20 |

**Recommendation:** Deploy on L2 (Base, Arbitrum) for cost-effective referrals.

---

## v2.2 Proxy Deployment (FixerRegistryUpgradeable)

### Overview

The upgradeable registry uses the UUPS proxy pattern (ERC1967Proxy). Deployment is a two-step atomic operation:
1. Deploy the `FixerRegistryUpgradeable` implementation contract
2. Deploy `ERC1967Proxy` pointing to the implementation, calling `initialize()` in the same transaction

### Deployment Script

**File:** `script/DeployUpgradeable.s.sol`

```bash
# Dry run
forge script script/DeployUpgradeable.s.sol --rpc-url $RPC_URL

# Deploy + verify
forge script script/DeployUpgradeable.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Required Environment Variables

```bash
PRIVATE_KEY=0x...           # Deployer (becomes owner)
SECURITY_COUNCIL=0x...      # Multisig for emergency pause
GOVERNANCE=0x...            # DAO governance address
TREASURY=0x...              # Protocol fee treasury
BUYBACK_CONTRACT=0x...      # Buyback module address
STAKER_REWARDS=0x...        # Staker reward distributor
```

### Post-Deployment Verification

```bash
# Verify proxy points to correct implementation
cast call <PROXY_ADDRESS> "UPGRADE_INTERFACE_VERSION()" --rpc-url $RPC_URL
# Expected: "5.0.0"

# Verify initialization
cast call <PROXY_ADDRESS> "name()" --rpc-url $RPC_URL
# Expected: "FixerToken"

cast call <PROXY_ADDRESS> "symbol()" --rpc-url $RPC_URL
# Expected: "FIX"

cast call <PROXY_ADDRESS> "owner()" --rpc-url $RPC_URL
# Expected: deployer address

# Verify protocol fee
cast call <PROXY_ADDRESS> "getProtocolFee()" --rpc-url $RPC_URL
# Expected: 500 (5%)

# Verify emergency state
cast call <PROXY_ADDRESS> "getEmergencyState()" --rpc-url $RPC_URL
```

### Addresses to Record

After deployment, save these addresses in your deployment log:
- **Implementation:** The raw `FixerRegistryUpgradeable` contract
- **Proxy:** The `ERC1967Proxy` (this is the address users interact with)
- **Admin:** The owner address (deployer by default)

> **Important:** All interactions go through the **proxy** address, never the implementation directly.

---

## Upgrade Process

### Overview

Upgrading deploys a new implementation and points the proxy to it. State is preserved in the proxy's storage.

**File:** `script/Upgrade.s.sol`

### Pre-Upgrade Checklist

- [ ] New implementation compiled and tested locally
- [ ] Storage layout compatibility verified (no slot conflicts)
- [ ] All new tests passing (`forge test`)
- [ ] Upgrade script dry-run successful
- [ ] Governance approval obtained (if required)

### Upgrade Commands

```bash
# Set the proxy address
export PROXY_ADDRESS=0x...

# Dry run
forge script script/Upgrade.s.sol --rpc-url $RPC_URL

# Execute upgrade
forge script script/Upgrade.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Post-Upgrade Verification

```bash
# Verify version bumped
cast call <PROXY_ADDRESS> "VERSION()" --rpc-url $RPC_URL

# Verify state preserved (check a known referrer's stats)
cast call <PROXY_ADDRESS> "referrerStats(address)" <KNOWN_REFERRER> --rpc-url $RPC_URL

# Verify new functionality works (if applicable)
```

### Rollback

UUPS proxies **do not support direct rollback**. If an upgrade has issues:
1. Deploy the previous implementation version as a new contract
2. Call `upgradeToAndCall()` to point back to the previous logic
3. This requires the owner to still have upgrade authority

---

## Deployment Checklist

### v1 (FixerHook)
- [ ] PoolManager address verified
- [ ] Private key secured (never commit to git)
- [ ] Hook address has correct permission bits
- [ ] Contract verified on block explorer
- [ ] Test swap executed successfully
- [ ] Token minting confirmed
- [ ] Frontend updated with hook address

### v2.2 (FixerRegistryUpgradeable)
- [ ] Security council is a multisig
- [ ] Governance address set correctly
- [ ] Fee addresses (treasury, buyback, stakers) set
- [ ] `initialize()` called atomically in deployment
- [ ] Proxy verified on block explorer
- [ ] Implementation verified on block explorer
- [ ] `owner()` returns expected deployer
- [ ] Emergency state is all-unpaused
- [ ] Protocol fee is 500 bps (5%)
- [ ] `authorizedHooks` set for FixerHook address

---

## Troubleshooting

### Address Mismatch Error

```
Error: Deployed address mismatch
```

**Solution:** Ensure the deployer address matches what was used for salt mining.

### Permission Bits Error

```
Error: Invalid hook address
```

**Solution:** The computed address doesn't have required permission bits. Increase iteration limit in HookMiner.

### Verification Failed

```
Error: Contract verification failed
```

**Solution:** Check constructor arguments are correctly encoded. Use `cast abi-encode` to verify.

---

## References

- [Uniswap v4 Hook Deployment](https://docs.uniswap.org/)
- [Foundry Deployment Scripts](https://book.getfoundry.sh/tutorials/solidity-scripting)
- [CREATE2 Address Computation](https://eips.ethereum.org/EIPS/eip-1014)
