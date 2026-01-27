# Security Analysis

> Threat Model and Mitigation Strategies for the Referral Hook

---

## Threat Model Overview

| Category | Risk Level | Status |
|----------|------------|--------|
| Self-Referral | Medium | Mitigated |
| Sybil Attacks | Medium | Partially Mitigated |
| Reentrancy | Low | Safe |
| Access Control | Low | Safe |
| Gas Griefing | Low | Safe |

---

## Attack Vectors Analysis

### 1. Self-Referral Prevention

**Attack:** User sets themselves as referrer to earn tokens on their own swaps.

**Mitigation:**
```solidity
if (referrer != tx.origin) {
    _mint(referrer, REWARD_AMOUNT);
}
```

**Analysis:**
- `tx.origin` captures the EOA that initiated the transaction
- Even if user swaps through a router contract, `tx.origin` identifies them
- Effective against direct self-referral

**Limitation:** 
- User with two wallets can still cross-refer
- See Sybil Attack section

---

### 2. Sybil Attack (Multi-Wallet Farming)

**Attack:** User creates multiple wallets and swaps between them to farm REF tokens.

**Current Mitigation:** None in MVP

**Proposed Solutions:**

| Solution | Complexity | Effectiveness |
|----------|------------|---------------|
| Minimum swap volume threshold | Low | Medium |
| Cooldown per referrer | Medium | Medium |
| Reputation scoring | High | High |

**Volume-Based Mitigation:**
```solidity
// Only reward swaps above threshold
int256 swapAmount = params.amountSpecified;
if (swapAmount < 0) swapAmount = -swapAmount;
if (uint256(swapAmount) < MIN_SWAP_AMOUNT) {
    return (BaseHook.afterSwap.selector, 0);
}
```

---

### 3. tx.origin Security Considerations

**Common Warning:** `tx.origin` should never be used for authentication.

**Our Use Case:** We use `tx.origin` for **anti-gaming**, not authentication.

| Use | Safe? | Rationale |
|-----|-------|-----------|
| Authentication | No | Vulnerable to phishing |
| Anti-gaming check | Yes | Prevents simple self-referral |

**Why it's safe here:**
- We're not authorizing any privileged action
- Worst case: a false negative (legitimate referral blocked)
- No funds at risk from tx.origin usage

---

### 4. Zero Address Check

**Attack:** Submit `address(0)` as referrer.

**Mitigation:**
```solidity
if (referrer != address(0)) {
    _mint(referrer, REWARD_AMOUNT);
}
```

**Result:** Minting to zero address would burn tokens. Check prevents this.

---

### 5. Reentrancy Analysis

**Risk Level:** Low

**Analysis:**
- ERC20 `_mint` is the only state change
- No external calls after state changes
- Follows checks-effects-interactions pattern

**Solmate ERC20 _mint:**
```solidity
function _mint(address to, uint256 amount) internal virtual {
    totalSupply += amount;               // State change
    balanceOf[to] += amount;             // State change
    emit Transfer(address(0), to, amount); // Event (no external call)
}
```

No reentrancy vector exists.

---

### 6. Gas Griefing

**Attack:** Submit malformed `hookData` to cause revert and waste gas.

**Mitigation:** `abi.decode` will revert on invalid data, but:
- User pays for their own failed transaction
- No griefing vector against other users
- Pool operation is not disrupted

---

## Permission Security

### Minimal Hook Permissions

We only enable `afterSwap`, reducing attack surface:

```solidity
Hooks.Permissions({
    beforeSwap: false,      // Can't front-run
    afterSwap: true,        // Only observation
    beforeSwapReturnDelta: false,  // Can't modify amounts
    afterSwapReturnDelta: false    // Can't modify results
});
```

**Benefit:** Hook cannot:
- Block or delay swaps
- Modify swap parameters
- Steal user funds
- Front-run transactions

---

## Recommendations

### For MVP
1. Self-referral check (implemented)
2. Zero address check (implemented)
3. Document Sybil risk to users

### For Production
1. Add minimum swap volume threshold
2. Consider per-referrer cooldowns
3. Implement governance for parameter changes
4. Add emergency pause functionality

---

## Audit Checklist

- [ ] All state changes follow checks-effects-interactions
- [ ] No unchecked external calls
- [ ] Hook permissions are minimal
- [ ] tx.origin usage is documented and justified
- [ ] Token minting cannot overflow (Solmate handles this)
- [ ] No selfdestruct or delegatecall vulnerabilities

---

## References

- [Uniswap v4 Security Considerations](https://docs.uniswap.org/)
- [Solmate ERC20 Implementation](https://github.com/transmissions11/solmate)
- [OpenZeppelin Security Best Practices](https://docs.openzeppelin.com/contracts/)
