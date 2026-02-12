# Linxir Smart Contracts

This repository contains the core smart contracts of the **Linxir ecosystem**, deployed and verified on **Ethereum Mainnet**.

The system is designed with a strong focus on:
- security
- modularity
- controlled token distribution
- vesting-based anti-dump mechanics
- future extensibility (privacy layer, migration)

All contracts have been:
- unit tested
- fuzz tested (Echidna)
- statically analyzed (Slither)
- deployed and verified on mainnet

---

## Contracts Overview

### 1. LinxirToken.sol
**Main ERC20 token contract**

Responsibilities:
- ERC20 token logic
- multi-source vesting system
- presale phase management
- staking balance exclusion
- controlled internal wallets
- migration support
- transfer fee support (optional)

Key features:
- Dynamic vesting based on presale phase
- Multiple vesting sources (Presale, Team, Marketing, Gaming, Staking)
- Anti-dump protections
- Migration-ready architecture
- Audit-oriented structure and comments

Mainnet:
LinxirToken: 0x1bd05590ab5cb8Aa541a0F997Ba0B40f9570124C

---

### 2. LinxirPresale.sol
**Token presale contract**

Responsibilities:
- Token sale in ETH and USDT
- Dynamic pricing across multiple phases
- Integration with LinxirToken vesting system
- Automatic phase progression
- Chainlink ETH/USD price feed usage

Key features:
- Multi-phase presale with progressive pricing
- ETH and USDT support
- On-chain USD normalization
- Non-reentrant design
- Treasury-based fund collection

Mainnet:
LinxirPresale: 0xC7C2626C1387A366EC2c353d8aeD786327710e05

---

### 3. LinxirStaking.sol
**Staking contract**

Responsibilities:
- Logical staking (no token transfers)
- APR-based reward calculation
- Time-based reward unlocking
- Vesting-based reward distribution

Key features:
- Tokens remain in user wallet
- balanceOf adjusted via LinxirToken
- Claimable rewards with vesting
- Anti-abuse timing restrictions

Mainnet:
LinxirStaking: 0xCBbB18386812c765be4f8B3Afc896Bb1DdA49bF4

---

### 4. LinxirGaming.sol
**Gaming integration contract**

Responsibilities:
- Handle gaming-related token deposits
- Track source and phase of deposited tokens
- Vest rewards and refunds
- Controlled burn / reinvest logic

Key features:
- Full compatibility with LinxirToken vesting
- Clear accounting per source
- Designed for future gaming mechanics

Mainnet:
LinxirGaming: 0xf6e5F6b4a679375eBAe963B1FB9B978268f8556f

---

## Security Measures

- Solidity ^0.8.x (overflow checks enabled)
- OpenZeppelin contracts
- ReentrancyGuard where applicable
- Strict access control
- Explicit wallet separation
- Defensive programming patterns
- Migration-aware logic

---

## Testing & Analysis

### Unit Tests
- Written using Foundry
- Core logic validated
- Edge cases covered

### Fuzz Testing
- Echidna-based fuzzing
- Supply invariants verified
- No critical violations found

### Static Analysis
- Slither analysis executed
- No critical vulnerabilities detected

---

## Deployment

All contracts were deployed using **Foundry scripts**.

- Network: Ethereum Mainnet
- Deployment method: deterministic scripts
- Transactions recorded in `/broadcast`

---

## Architecture Notes

- Internal wallets are configurable and updatable
- Presale, staking, and gaming contracts are linked post-deployment
- Initial distribution executed only after full system deployment
- Designed for future Layer-2 / privacy-chain migration

---

## Audit Status

- Internal audit completed
- Automated analysis completed
- Professional third-party audit planned

---

## Disclaimer

This repository is provided as-is.  
The Linxir ecosystem is under active development.  
Smart contracts may evolve as the project progresses.

---

## 👤 Author

Linxir Team



