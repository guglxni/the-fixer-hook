# Security Analysis

> The Fixer Hook Protocol — Threat Model and Mitigations (v2.6.0)

**Last Updated:** February 26, 2026 | **Version:** 2.6.0

---

## Table of Contents

1. [Threat Model](#threat-model)
2. [Hook Security](#hook-security)
3. [UUPS Proxy Security](#uups-proxy-security)
4. [DELEGATECALL Extension Security](#delegatecall-extension-security)
5. [Emergency Module](#emergency-module)
6. [Token Security](#token-security)
7. [Agent Infrastructure Security](#agent-infrastructure-security)
8. [EIP-3009 / x402 Security](#eip-3009--x402-security)
9. [XMTP Security](#xmtp-security)
10. [Known Limitations](#known-limitations)
11. [Audit Checklist](#audit-checklist)

---

## Threat Model

### Attack Surfaces

| Surface | Risk Level | Description |
|---------|:----------:|-------------|
| Self-referral (Sybil) | Medium | Attacker refers themselves to farm FIX tokens |
| Reward amplification | Medium | Stacking tier × reputation bonuses beyond intended limits |
| Proxy upgrade hijack | Critical | Unauthorized contract upgrade to drain funds |
| DELEGATECALL storage corruption | High | Extension writing to unexpected storage slots |
| Circuit breaker bypass | Medium | Minting past hourly/daily limits |
| ERC-8004 reputation manipulation | Low | Inflating reputation score for higher bonuses |
| EIP-3009 replay attacks | Medium | Replaying gasless transfer authorizations |
| XMTP endpoint spoofing | Low | Setting malicious XMTP endpoints |
| Reentrancy | High | Re-entering recordReferral during mint |
| Gas griefing | Low | Passing expensive hookData to increase gas costs |

---

## Hook Security

### Self-Referral Prevention

```solidity
// FixerHookV2._afterSwap()
address swapper = _resolveSwapper(sender);
if (referrer == address(0) || referrer == swapper) {
    return (this.afterSwap.selector, 0);
}
```

**Mitigation layers:**
1. **`tx.origin` fallback** — identifies actual transaction initiator (not router contract)
2. **Trusted Router Pattern** — `IMsgSender(router).msgSender{gas: 50_000}()` resolves account-abstracted wallets
3. **Gas-capped call** — 50,000 gas limit prevents griefing via malicious router implementations
4. **Volume-based tiers** — farming requires substantial capital to reach higher multipliers

### tx.origin Justification

Using `tx.origin` is intentional and appropriate here:
- **NOT used for authentication** — only as a heuristic to identify the swapper
- **Fallback only** — trusted routers use `msgSender()` first
- **Anti-gaming purpose** — prevents the trivial case where `msg.sender` is always a router

### Observation-Only Pattern

```solidity
return (this.afterSwap.selector, int128(0));
//                                ^^^^^^^^ NEVER modifies swap deltas
```

The hook returns zero delta modification. This means:
- **No funds at risk** from the hook contract itself
- Swap execution is identical with or without the hook
- Only gas cost is added (not token risk)

### hookData Validation (F-05)

```solidity
try this.decodeReferrer(hookData) returns (address referrer) {
    // valid
} catch {
    return (this.afterSwap.selector, 0);  // graceful failure
}
```

Malformed hookData is caught via try/catch on a public `decodeReferrer()` function (self-call pattern). This prevents reverts from blocking legitimate swaps.

### Numeric Safety (F-13, F-18)

- **int128.min guard:** `int128(-2^127)` cannot be safely negated — explicitly handled
- **uint128 bounds:** all volume calculations use uint128 with overflow checks

---

## UUPS Proxy Security

### Initialization Front-Running

**Risk:** Attacker calls `initialize()` before the deployer.

**Mitigation:** Deploy script calls `initialize()` in the same transaction as proxy creation (atomic deployment). The `initializer` modifier prevents re-initialization.

### 48-Hour Upgrade Timelock

```solidity
function proposeUpgrade(address newImplementation) external onlyOwner {
    s.upgradeProposal = UpgradeProposal({
        implementation: newImplementation,
        proposedAt: block.timestamp,
        executed: false,
        version: VERSION
    });
}

function executeUpgrade(address newImplementation) external onlyOwner {
    require(block.timestamp >= proposal.proposedAt + UPGRADE_TIMELOCK); // 48h
    // ... validate and upgrade
}

function _authorizeUpgrade(address newImpl) internal override onlyOwner {
    // BLOCKS direct upgradeToAndCall() — must go through propose/execute
    require(s.upgradeProposal.implementation == newImpl);
    require(block.timestamp >= s.upgradeProposal.proposedAt + UPGRADE_TIMELOCK);
}
```

**Defense-in-depth:**
- `proposeUpgrade()` starts 48h timer
- `cancelUpgrade()` available to owner/security council
- `_authorizeUpgrade()` validates proposal exists and timelock expired
- Direct `upgradeToAndCall()` without prior proposal will revert

### ERC-7201 Storage Safety

Namespaced storage at a deterministic slot prevents collision with:
- OpenZeppelin's own storage (ERC20Upgradeable, OwnableUpgradeable, etc.)
- Future upgrades adding new state variables
- 38 gap slots reserved for expansion

---

## DELEGATECALL Extension Security

### Storage Sharing Risks

The Extension executes via DELEGATECALL and shares the same storage layout:

**Risk:** Extension could corrupt Core storage if layouts differ.

**Mitigations:**
1. **Both contracts inherit the same `FixerRegistryStorage`** — identical ERC-7201 struct
2. **Extension only accesses mapped fields** (agentProfiles, delegations, XMTP state) — these are appended after Core fields
3. **38 gap slots** prevent layout collision with future additions
4. **Extension is set by owner** via `setExtension()` — not user-controlled

### Fallback Routing

```solidity
fallback() external payable {
    address ext = _getMainStorage().extension;
    require(ext != address(0));
    assembly {
        calldatacopy(0, 0, calldatasize())
        let result := delegatecall(gas(), ext, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
    }
}
```

**Risk:** Unknown selectors routed to extension could collide with extension internals.

**Mitigation:** Extension only exposes explicitly defined external functions. Internal functions use `internal` visibility and cannot be called via DELEGATECALL.

---

## Emergency Module

### 3 Independent Pause States

| State | Controls | Effect |
|-------|----------|--------|
| `pauseReferrals` | Referral recording | Swaps succeed but no FIX minted |
| `pauseAgents` | Agent registration | New agents cannot register |
| `pauseRewards` | All FIX minting | Global mint freeze |

### Security Council Fast-Path

The security council (multisig) can:
- **Pause instantly** — no timelock required
- Work alongside DAO governance — council for speed, DAO for permanence

### DAO Governance Threshold (F-04)

After 7 days of continuous pause, only DAO governance can resume. If governance is `address(0)` (not yet set), the security council retains resume authority as a safety fallback.

### Circuit Breaker

```
Hourly limit: 1,000,000 FIX (default, range: 100K–50M)
Daily ceiling: 10,000,000 FIX (hard cap, not configurable)
```

When either limit is breached, rewards auto-pause. This prevents:
- Exploit-driven mass minting
- Economic attacks during market manipulation
- Buggy integrations draining supply

### pauseAll / resumeAll Atomicity (F-03, F-16)

- `pauseAll()` does NOT reset existing pause timestamps — preserves the 7-day DAO threshold clock
- `resumeAll()` reverts with `NothingPaused()` if nothing is actually paused

---

## Token Security

### Supply Cap (F-07)

```solidity
function _update(address from, address to, uint256 amount) internal override {
    if (from == address(0)) { // mint
        require(totalSupply() + amount <= MAX_SUPPLY); // 1B FIX
    }
    super._update(from, to, amount);
}
```

Hard cap is enforced at the token level, not just in `recordReferral()`. Even owner minting cannot exceed 1B.

### MAX_GROSS_REWARD Cap

```solidity
uint256 constant MAX_GROSS_REWARD = 5000e18; // 5,000 FIX
```

Prevents tier (2.0x) × reputation (1.5x) amplification from creating outsized rewards per swap. Even a Platinum referrer with Elite reputation gets at most 5,000 FIX/swap.

### Protocol Fee Bounds

```solidity
uint64 constant MAX_PROTOCOL_FEE_BPS = 1000; // 10% hard cap
```

Owner cannot set protocol fee above 10%. Default is 5%.

---

## Agent Infrastructure Security

### ERC-8004 Agent Registration

**Permissionless but verified:**
1. Agent calls `registerAgent(agentId, platform)`
2. `FixerLib.validateAgent()` checks:
   - `IERC8004IdentityRegistry.ownerOf(agentId) == msg.sender`
   - `IERC8004IdentityRegistry.getAgentWallet(agentId) == msg.sender`
   - Optional: validation score from IERC8004ValidationRegistry
3. If any check fails, registration reverts

**Risk:** Fake ERC-8004 registries could approve any agent.

**Mitigation:** Registry addresses are set by owner and immutable per version. Only trusted ERC-8004 implementations are configured.

### Reputation Cache Manipulation

**Risk:** Stale reputation data used to maintain inflated bonuses.

**Mitigation:**
- Cache TTL: 1 hour (configurable 10min–24h)
- Stale cache (>TTL) auto-degrades bonus by 50%
- `refreshAgentReputation()` can be called by anyone to force update
- All reputation reads wrapped in try/catch to handle registry failures

### Referral Delegation

**Risk:** Delegator earns rewards through delegatee's actions without actual contribution.

**Mitigation:**
- One-to-one delegation only
- Delegator must be a registered referrer
- Delegation is revocable at any time
- Delegatee cannot further sub-delegate

---

## EIP-3009 / x402 Security

### Replay Prevention

```solidity
function transferWithAuthorization(
    address from, address to, uint256 value,
    uint256 validAfter, uint256 validBefore, bytes32 nonce,
    uint8 v, bytes32 r, bytes32 s
) external {
    require(block.timestamp > validAfter && block.timestamp < validBefore);
    require(!authorizationStates[from][nonce]); // nonce consumed
    // ... ECDSA.recover validates signature against EIP-712 domain
    authorizationStates[from][nonce] = true;
    _transfer(from, to, value);
}
```

**Protections:**
- **Nonce-based replay prevention** — each nonce can only be used once
- **Time-bounded validity** — `validAfter` / `validBefore` window
- **EIP-712 domain separation** — signature is chain-specific and contract-specific
- **ECDSA.recover** via Solady — validates signer matches `from`

---

## XMTP Security

### Endpoint Validation

- **Max URI length:** 256 bytes (`XMTPConstants.MAX_ENDPOINT_URI_LENGTH`)
- **Non-zero public key hash** required to enable XMTP
- **Agent must be registered** before enabling XMTP
- **Counter tracking:** `xmtpEnabledCount` tracks active XMTP agents

### Threat: Endpoint Spoofing

**Risk:** Agent sets malicious XMTP endpoint to phish other agents.

**Mitigation:** XMTP endpoints are informational/discovery only. Actual XMTP communication is encrypted end-to-end. Consumers should verify agent identity via ERC-8004 before trusting endpoint data.

---

## Known Limitations

| Limitation | Impact | Rationale |
|-----------|--------|-----------|
| `tx.origin` for swapper identification | Won't work via smart contract wallets without trusted router | Acceptable tradeoff — trusted router pattern handles most cases |
| Single-chain registries | No cross-chain referral aggregation | Each chain has independent state; Reactive Network (Lasna) enables cross-chain monitoring |
| ERC-8004 registry trust | Depends on correct registry addresses | Owner-set, immutable per version |
| No on-chain governance yet | Owner controls all admin functions | Planned for mainnet with veFIX governance |

---

## Audit Checklist

### v1.0 Fixes Applied

| ID | Issue | Fix |
|----|-------|-----|
| F-05 | Malformed hookData reverts block swaps | try/catch self-call pattern |
| F-06 | Credential mint reentrancy | Set all state before `_safeMint` |
| F-07 | No supply cap | MAX_SUPPLY 1B enforced in `_update()` |
| F-08 | No admin rotation | Ownable (Solady) for FixerHookV2 |

### v2.x Fixes Applied

| ID | Issue | Fix |
|----|-------|-----|
| F-03 | `pauseAll()` resets timestamps | Preserves existing pause timestamps |
| F-04 | DAO resume when governance not set | Security council fallback if governance == address(0) |
| F-13 | int128.min cannot be negated | Explicit guard in volume calculation |
| F-14 | Gas griefing via router.msgSender() | 50,000 gas cap on external call |
| F-16 | `resumeAll()` when nothing paused | Reverts with NothingPaused() |
| F-17 | Soulbound NFT transfer bypass | All transfer/approve functions revert TokenLocked() |
| F-18 | uint128 overflow in volume calc | Explicit bounds checking |
| N-03 | int128.min guard completeness | Added to all int128 conversion paths |

### v2.6 Audit Items

| Area | Status | Details |
|------|:------:|---------|
| DELEGATECALL storage alignment | ✓ | Both contracts use identical ERC-7201 struct |
| Extension selector collision | ✓ | No overlap between Core and Extension external functions |
| XMTP endpoint validation | ✓ | Length limit + non-zero key + agent check |
| EIP-3009 nonce management | ✓ | Single-use nonces with time bounds |
| Reputation cache degradation | ✓ | 50% bonus reduction on stale cache |
| Circuit breaker hourly/daily | ✓ | Both limits enforced independently |
| MAX_GROSS_REWARD enforcement | ✓ | 5,000 FIX cap prevents amplification |
| Upgrade timelock integrity | ✓ | 48h enforced in `_authorizeUpgrade()` |

---

<p align="center">
  <em>Document Version: 3.0.0 | Last Updated: February 26, 2026</em>
</p>
