# Audit Scope — Linxir Smart Contracts

This document defines the **scope, objectives, assumptions, and exclusions** for the security audit of the Linxir smart contract system.

---

## In-Scope Contracts

The following contracts are **explicitly included** in the audit scope:

### Core Contracts
- `LinxirToken.sol`
- `LinxirPresale.sol`
- `LinxirStaking.sol`
- `LinxirGaming.sol`

All contracts are deployed and verified on **Ethereum Mainnet**.

---

## 🔗 System Architecture Overview

The Linxir system is composed of modular smart contracts with clear separation of responsibilities:

- **LinxirToken**  
  Core ERC20 token with advanced vesting, presale phase logic, staking balance exclusion, migration support, and internal wallet controls.

- **LinxirPresale**  
  Handles token sales in ETH and USDT with dynamic pricing, Chainlink price feeds, and vesting-based token delivery.

- **LinxirStaking**  
  Implements logical staking without token transfers, APR-based rewards, and vesting-based reward distribution.

- **LinxirGaming**  
  Manages gaming-related deposits, rewards, vesting logic, and optional burn/reinvest mechanics.

All contracts interact through explicit interfaces and controlled permissions.

---

## Audit Objectives

The primary objectives of the audit are to:

- Identify **critical, high, and medium severity vulnerabilities**
- Validate correctness of:
  - vesting logic
  - presale phase progression
  - staking reward calculations
  - internal wallet management
- Detect potential:
  - reentrancy risks
  - arithmetic issues
  - access control flaws
  - privilege escalation vectors
- Review system behavior under edge cases and adversarial conditions
- Assess upgrade and migration safety assumptions

---

## Security Assumptions

The following assumptions apply:

- The Ethereum Mainnet behaves according to its documented consensus rules
- Chainlink ETH/USD price feeds return valid prices
- USDT (ERC20) behaves according to its official deployed implementation
- Private keys of privileged roles are securely managed off-chain
- No malicious behavior from authorized wallets unless explicitly tested

---

## Out-of-Scope Items

The following items are **explicitly excluded** from the audit scope:

- Frontend code (web, mobile, dApp UI)
- Backend infrastructure
- Off-chain services and APIs
- Legal, regulatory, or compliance analysis
- Token price, market performance, or financial guarantees
- Social engineering or phishing vectors
- Governance decisions external to smart contracts

---

## Testing & Tooling Context

The following tooling has already been applied prior to third-party audit:

- **Unit testing** via Foundry
- **Fuzz testing** via Echidna
- **Static analysis** via Slither
- **Manual internal review**

Audit findings should be evaluated in context of the above baseline.

---

## Deployment Context

- Network: Ethereum Mainnet
- Deployment tool: Foundry scripts
- Deploy transactions and artifacts available in `/broadcast`
- All contracts verified on-chain

---

## Known Design Decisions

The following design choices are intentional and should not be flagged as issues:

- Use of placeholder wallet addresses during initial deployment
- Post-deployment linking of contracts via setter functions
- Logical staking without token transfers
- Vesting-based restriction of transferable balances
- Controlled internal wallets with special permissions

---

## Deliverables Expected

Auditors are expected to provide:

- A detailed vulnerability report
- Severity classification (Critical / High / Medium / Low / Informational)
- Proof-of-concept where applicable
- Recommendations and mitigation strategies
- Final audit summary

---

## Maintainer

Linxir Core Team
