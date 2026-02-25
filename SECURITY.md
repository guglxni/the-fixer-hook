# Security Policy

> Vulnerability Disclosure Policy & Bug Bounty Program for the FixerHook Protocol

**Version:** 2.0
**Effective Date:** February 2025
**Last Updated:** February 2026

---

## Reporting a Vulnerability

**DO NOT** open a public GitHub issue for security vulnerabilities.

### Preferred Disclosure Method

1. **Email:** Send a detailed report to **security@fixerhook.xyz** (PGP key available on request)
2. **Immunefi:** Submit via our Immunefi bounty page (if active)

### What to Include

- Description of the vulnerability and its potential impact
- Step-by-step reproduction instructions
- Proof-of-concept code (Foundry test preferred)
- Affected contract(s) and function(s)
- Suggested severity (see classification below)

### Response Timeline

| Phase | Timeframe |
|-------|-----------|
| Acknowledgment | Within 48 hours |
| Triage & Severity Assessment | Within 5 business days |
| Fix Development | 1–4 weeks (severity-dependent) |
| Disclosure (coordinated) | 30 days after fix deployment |

---

## Scope

### In-Scope Contracts

| Contract | Path | Version |
|----------|------|---------|
| FixerRegistryUpgradeable | `src/FixerRegistryUpgradeable.sol` | v2.4.0 |
| EmergencyModule | `src/modules/EmergencyModule.sol` | v2.4.0 |
| FixerHookV2 | `src/FixerHookV2.sol` | v2.0.0 |
| FixerRegistryStorage | `src/storage/FixerRegistryStorage.sol` | v2.4.0 |
| BPSMath | `src/libraries/BPSMath.sol` | v1.0.0 |
| IAgentRegistry | `src/interfaces/IAgentRegistry.sol` | v2.4.0 |
| IERC8004IdentityRegistry | `src/interfaces/IERC8004IdentityRegistry.sol` | v2.4.0 |
| IERC8004ReputationRegistry | `src/interfaces/IERC8004ReputationRegistry.sol` | v2.4.0 |
| IERC8004ValidationRegistry | `src/interfaces/IERC8004ValidationRegistry.sol` | v2.4.0 |

### In-Scope Vulnerability Categories

- **Smart Contract Logic:** Incorrect state transitions, missing access controls, logic errors
- **Economic Exploits:** Price manipulation, flash-loan attacks, reward gaming
- **Proxy/Upgrade Risks:** Storage collision, initialization front-running, unauthorized upgrades
- **Emergency System Bypass:** Circuit breaker circumvention, pause mechanism bypass
- **Denial of Service:** Gas griefing, storage bloat, block stuffing
- **Reentrancy:** Cross-function or cross-contract reentrancy
- **Token Minting:** Unauthorized minting, supply cap bypass, daily ceiling circumvention
- **ERC-8004 Identity:** NFT ownership spoofing, registration bypass, wallet mismatch exploits
- **Reputation Gaming:** Cache manipulation, stale score exploitation, bonus tier inflation
- **External Call Safety:** Revert-based DoS on ERC-8004 registry calls, missing try/catch

### Out of Scope

- Frontend/UI vulnerabilities
- Third-party dependency vulnerabilities (OpenZeppelin, Uniswap v4-core)
- Issues already documented in `docs/SECURITY.md` threat model
- Centralization risks inherent to the owner role (documented, accepted)
- Theoretical attacks without a feasible proof-of-concept
- Gas optimization suggestions
- v1 contracts (`FixerHook.sol`, `FixerRegistry.sol`) — deprecated

---

## Severity Classification

We follow the **OWASP Smart Contract Risk Rating** adapted for DeFi:

### Critical (Score 9.0–10.0)

**Impact:** Direct loss of user funds, permanent protocol freeze, unlimited token minting

| Example | Impact |
|---------|--------|
| MAX_SUPPLY bypass allowing unlimited FIX minting | Token value destruction |
| UUPS upgrade hijack (storage collision) | Full protocol takeover |
| Reentrancy draining accumulated fees | Direct fund loss |

**Reward Range:** $5,000 – $25,000

### High (Score 7.0–8.9)

**Impact:** Significant economic damage, privilege escalation, temporary fund lock

| Example | Impact |
|---------|--------|
| Circuit breaker bypass enabling excessive minting | Inflation attack |
| Emergency pause circumvention | Security system failure |
| Tier manipulation for unearned rewards | Economic exploitation |

**Reward Range:** $2,000 – $5,000

### Medium (Score 4.0–6.9)

**Impact:** Limited economic damage, griefing, state inconsistency

| Example | Impact |
|---------|--------|
| Self-referral bypass (tx.origin check circumvention) | Reward gaming |
| Sybil attacks on referral counting | Inflated metrics |
| Daily mint ceiling bypass via timestamp manipulation | Moderate over-minting |

**Reward Range:** $500 – $2,000

### Low (Score 1.0–3.9)

**Impact:** Informational, gas inefficiency, minor state issues

| Example | Impact |
|---------|--------|
| Event emission ordering issues | Off-chain tracking discrepancy |
| Redundant storage reads | Gas waste |
| Missing NatSpec documentation | Developer experience |

**Reward Range:** $100 – $500

---

## Reward Eligibility

### Qualifying Criteria

- First reporter of a previously unknown vulnerability
- Vulnerability must be reproducible via a Foundry test or clear reproduction steps
- Must be in-scope (see above)
- Responsible disclosure followed (no public disclosure before fix)

### Disqualifying Actions

- Public disclosure before coordinated fix
- Exploiting the vulnerability on mainnet
- Social engineering or phishing attacks on team members
- Automated scanner output without manual verification
- Duplicate reports of known issues

---

## Safe Harbor

We consider security research conducted under this policy to be:

- **Authorized** in accordance with the Computer Fraud and Abuse Act (CFAA)
- **Exempt** from DMCA restrictions on circumvention
- **Lawful** and conducted in good faith

We will not pursue legal action against researchers who:

1. Follow this disclosure policy
2. Avoid accessing or modifying user funds
3. Do not degrade protocol availability
4. Report findings promptly

---

## Security Architecture Summary

For detailed threat modeling and mitigation strategies, see [`docs/SECURITY.md`](docs/SECURITY.md).

### Key Security Features

| Feature | Description |
|---------|-------------|
| **UUPS Proxy** | Upgradeable with 48-hour timelock proposal system |
| **ERC-7201 Storage** | Namespaced storage prevents collision across upgrades |
| **Emergency Module** | Security council fast-pause with 7-day DAO override |
| **Circuit Breaker** | Per-hour mint ceiling with MIN_CIRCUIT_BREAKER floor |
| **MAX_SUPPLY Cap** | Hardcoded 1B FIX ceiling enforced in `_update()` override |
| **Daily Mint Ceiling** | 10M FIX/day limit with DAO-owned council override |
| **ReentrancyGuard** | OpenZeppelin nonReentrant on all state-mutating functions |
| **BPSMath Library** | Centralized basis-point math preventing overflow |
| **ERC-8004 Identity** | Permissionless agent registration via NFT ownership proof |
| **Reputation Cache** | Configurable TTL (600s-86400s) with stale-cache grace degradation |
| **External Call Safety** | All ERC-8004 registry calls wrapped in `try/catch` |

---

## Audit Status

| Audit | Status | Date |
|-------|--------|------|
| Slither Static Analysis | Completed (0 high/medium) | Feb 2025 |
| Forge Coverage | >95% on production contracts | Feb 2026 |
| Forge Tests | 352 tests, 34 suites, 0 failures | Feb 2026 |
| Invariant Testing | 4 property-based tests | Feb 2025 |
| Formal Verification | Planned | TBD |
| External Audit | Planned | TBD |

---

## Contact

- **Security Email:** security@fixerhook.xyz
- **GitHub Security Advisories:** [Create advisory](../../security/advisories/new)
- **PGP Key:** Available on request

---

*This policy is subject to change. Researchers are encouraged to check for updates before submitting.*
