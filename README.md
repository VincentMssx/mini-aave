# Mini-Aave: A Simplified DeFi Lending Protocol

[![CI](https://github.com/VincentMssx/mini-aave/actions/workflows/ci.yml/badge.svg)](https://github.com/VincentMssx/mini-aave/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Mini-Aave is a simplified, educational implementation of a decentralized, non-custodial liquidity protocol inspired by Aave. It allows users to supply assets to earn interest and borrow assets against their collateral.

This project is built with Hardhat and Solidity and is intended to demonstrate the core mechanics of a DeFi lending market.

## Core Features (MVP)

*   **Deposit:** Users can deposit ERC20 assets into a reserve and receive interest-bearing aTokens in return. `deposit(asset, amount)`
*   **Withdraw:** Users can redeem their aTokens to withdraw their underlying assets. `withdraw(asset, amount)`
*   **Borrow:** Users can borrow assets against their supplied collateral, provided their position remains healthy. `borrow(asset, amount)`
*   **Repay:** Users can repay their outstanding debt for a borrowed asset. `repay(asset, amount)`
*   **Interest Accrual:** Interest rates are calculated dynamically based on supply and demand, using a cumulative index model (`supplyIndex`/`borrowIndex`).
*   **Price Oracles:** Integration with Chainlink Price Feeds for reliable, real-time asset valuation.
*   **Liquidation:** A mechanism for third parties to repay the debt of under-collateralized borrowers in exchange for their collateral at a discount. `liquidate(...)`
*   **Testing:** A comprehensive test suite covering all core functionalities, including adversarial scenarios.

## Stretch Goals

*   **Advanced Interest Rate Curves:** Implementing distinct stable and variable rate models.
*   **Flash Loans:** Support for uncollateralized loans that are repaid within the same transaction.
*   **Gasless Approvals:** Integration of EIP-2612 `permit` for an improved user experience.
*   **Upgradeable Contracts:** Using the UUPS or Transparent Proxy Pattern to allow for future upgrades.
*   **The Graph Subgraph:** Indexing protocol events for easy data querying.
*   **UI Demo:** A simple front-end built with Next.js to interact with the deployed contracts.

## Tech Stack

*   **Blockchain:** Solidity, Ethereum Virtual Machine (EVM)
*   **Development Framework:** Hardhat
*   **Libraries:** Ethers.js, TypeChain
*   **Standard Contracts:** OpenZeppelin Contracts, Chainlink Contracts
*   **Testing:** Chai, Mocha

## Project Structure

```
mini-aave/
├─ contracts/          # Main Solidity contracts
│ ├─ core/             # Core logic (LendingPool, Reserve)
│ ├─ tokens/           # aToken implementation
│ ├─ interest/         # Interest rate model logic
│ ├─ oracles/          # Chainlink price feed adapter
│ └─ mocks/            # Mock contracts for testing
├─ scripts/            # Deployment scripts
├─ test/               # Test files (Hardhat/Chai)
├─ .github/workflows/  # GitHub Actions for CI/CD
│  └─ ci.yml
├─ hardhat.config.ts   # Hardhat configuration
├─ package.json        # Project dependencies and scripts
├─ DESIGN.md           # High-level architecture document
└─ README.md           # This file
```

## Getting Started

### Prerequisites

*   [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
*   [Node.js](https://nodejs.org/en/) (v18 or later)
*   [npm](https://www.npmjs.com/) or [Yarn](https://yarnpkg.com/)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/VincentMssx/mini-aave.git
    cd mini-aave
    ```

2.  **Install dependencies:**
    ```bash
    npm install
    ```

### Environment Variables

To deploy to a testnet or mainnet, you will need to set up environment variables. Create a `.env` file in the root of the project and add the following variables:

```
PRIVATE_KEY="your-private-key"
ALCHEMY_API_KEY="your-alchemy-api-key"
ETHERSCAN_API_KEY="your-etherscan-api-key"
```

A `.env.example` file is provided as a template.

## Usage

### Compiling Contracts

```bash
npm run compile
```

### Running Tests

```bash
npm run test
```

### Deploying to a Network

To deploy the contracts to a network (e.g., Sepolia), run the following command:

```bash
npx hardhat run scripts/deploy.ts --network <network-name>
```

Replace `<network-name>` with the name of the network configured in `hardhat.config.ts`.