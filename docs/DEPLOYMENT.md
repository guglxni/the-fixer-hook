# Deployment Guide

> Deploy the Referral Hook to testnets and mainnet

---

## Overview

Uniswap v4 hooks require deployment to addresses with specific bits set based on enabled permissions. This guide covers the address mining and deployment process.

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

## Deployment Checklist

- [ ] PoolManager address verified
- [ ] Private key secured (never commit to git)
- [ ] Hook address has correct permission bits
- [ ] Contract verified on block explorer
- [ ] Test swap executed successfully
- [ ] Token minting confirmed
- [ ] Frontend updated with hook address

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
