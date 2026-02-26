# Mainnet Deployments

> Fixer Protocol v2.6 — Mainnet deployment guide and addresses (Coming Soon)

**Status:** Planned for Q2-Q3 2026
**Version:** 2.6.0 (VERSION constant: `2_006_000`)

---

## Overview

This document will contain live mainnet deployment addresses once the protocol is deployed to production networks. The Fixer Protocol is designed to deploy on multiple L2 networks for optimal gas costs and ecosystem support.

> **Note:** Mainnet deployments require thorough testing on testnets and security audits. This document will be updated once deployments are confirmed.

---

## Planned Networks

| Network | Chain ID | Status | Estimated Gas Cost |
|---------|----------|--------|-------------------|
| **Ethereum** | 1 | 🚧 Planned | 0.5-5 ETH |
| **Base** | 8453 | 🚧 Planned | ~0.01 ETH |
| **Arbitrum** | 42161 | 🚧 Planned | ~0.01 ETH |
| **Unichain** | 130 | 🚧 Planned | <0.001 ETH |
| **Lasna (Reactive)** | 5318007 | 🚧 Planned | <0.001 ETH |

---

## Pre-Deployment Checklist

Before deploying to mainnet, ensure:

- [ ] All testnet deployments verified and functioning
- [ ] Security audit completed by reputable firm
- [ ] Bug bounty program established
- [ ] Upgrade timelock (48 hours) tested on testnet
- [ ] Emergency pause functionality verified
- [ ] FIX token supply cap (1B) enforced
- [ ] All 381 tests passing (35 suites)
- [ ] Gas optimization complete (`via_ir = true`)
- [ ] Multisig wallets configured for security council
- [ ] Monitoring and alerting systems in place

---

## Deployment Commands

### Ethereum Mainnet

```bash
# Set environment variables
export ETHEREUM_MAINNET_RPC="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
export PRIVATE_KEY="0x..."
export ETHERSCAN_API_KEY="..."

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url ethereum \
  --broadcast \
  --verify \
  -vvvv
```

### Base Mainnet

```bash
# Set environment variables
export BASE_RPC="https://base-mainnet.g.alchemy.com/v2/YOUR_KEY"
export PRIVATE_KEY="0x..."
export BASESCAN_API_KEY="..."

# Deploy
forge script script/DeployBaseSepolia.s.sol \
  --rpc-url base \
  --broadcast \
  --verify \
  -vvvv
```

### Arbitrum Mainnet

```bash
# Set environment variables
export ARB_RPC="https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY"
export PRIVATE_KEY="0x..."
export ARBISCAN_API_KEY="..."

# Deploy
forge script script/DeployArbSepolia.s.sol \
  --rpc-url arb \
  --broadcast \
  --verify \
  -vvvv
```

---

## Expected Contracts

Each mainnet deployment will include:

1. **FixerRegistryUpgradeable (Implementation)** — UUPS logic contract (20.5KB core)
2. **FixerRegistryExtension** — DELEGATECALL extension for agents, XMTP, EIP-3009 (14.7KB)
3. **FixerLib** — External library for tier calculations and reward math (2.3KB)
4. **ERC1967Proxy** — Transparent proxy users interact with (the "Registry")
5. **FixerHookV2** — Uniswap v4 `afterSwap` hook (CREATE2-mined address)
6. **FixerCredential** — Soulbound ERC-721 reputation NFT

> **Note:** Lasna (Reactive Network) deploys registry-only (no hook, no FixerCredential).

---

## Mainnet-Specific Considerations

### Gas Optimization

Mainnet deployment costs are significantly higher than L2s. Recommended:

- Deploy during low gas periods
- Consider L2 deployment for initial launch
- Use `via_ir = true` in foundry.toml

### Token Economics

- **FIX Token Supply Cap:** 1,000,000,000 (1 billion)
- **Initial Distribution:** Referral rewards only
- **No ICO/Public Sale:** Token earned through protocol usage

### Security Considerations

- Multisig required for Security Council (3/5 recommended)
- 48-hour upgrade timelock enforced
- Emergency pause capability
- Protocol fee: 500 bps (5%)

---

## Post-Deployment Actions

After mainnet deployment:

1. **Verify Contracts**
   ```bash
   # Check VERSION
   cast call $PROXY "VERSION()(uint256)" --rpc-url $RPC
   # Should return: 2006000

   # Check ownership
   cast call $PROXY "owner()(address)" --rpc-url $RPC

   # Verify hook authorization
   cast call $PROXY "isAuthorizedHook(address)(bool)" $HOOK --rpc-url $RPC
   ```

2. **Update Documentation**
   - Record addresses in this file
   - Update README.md with mainnet addresses
   - Submit to block explorers for verification

3. **Announce Deployment**
   - Social media announcements
   - Documentation updates
   - Community tutorials

---

## Production Checklist

- [ ] Security audit completed
- [ ] Bug bounty program active
- [ ] All contracts verified on block explorers
- [ ] Multisig configured (3/5 Security Council)
- [ ] Monitoring dashboards operational
- [ ] Documentation finalized
- [ ] Community informed

---

## Support

For mainnet deployment assistance:

- [Discord](https://discord.gg/the-fixer)
- [Twitter](https://twitter.com/thefixerhook)
- [GitHub Issues](https://github.com/guglxni/the-fixer-hook/issues)

---

## Related Documentation

- [Deployment Guide](./DEPLOYMENT.md) — Detailed deployment procedures
- [Testnet Deployments](./TESTNET_DEPLOYMENTS.md) — Testnet addresses and instructions
- [Security Analysis](./SECURITY.md) — Threat model and mitigations
- [Integration Guide](./INTEGRATION_GUIDE.md) — Frontend integration

---

*Last Updated: February 23, 2026*
