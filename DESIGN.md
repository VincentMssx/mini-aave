# Mini-Aave Design Document

## 1. Overview

Mini-Aave is a simplified, non-custodial liquidity protocol inspired by Aave. It enables users to earn interest on supplied digital assets and borrow other assets against their supplied collateral. This document outlines the core architecture, key concepts, and user flows of the protocol's MVP (Minimum Viable Product).

## 2. Core Concepts

### 2.1 Reserves

Each supported asset in the protocol is managed within a **Reserve**. A reserve is a pool of liquidity for a single ERC20 token (e.g., WETH, DAI). It tracks key metrics like total supplied liquidity, total borrows, and the interest rate indices. The `LendingPool` contract manages a mapping of asset addresses to their `Reserve.Data` struct.

### 2.2 aTokens

When a user deposits an asset into a reserve, they receive a corresponding amount of **aTokens** (e.g., depositing WETH mints aWETH). aTokens are interest-bearing ERC20 tokens that represent a user's claim on the underlying asset in the reserve.

-   **Interest Accrual:** The value of an aToken increases over time as interest accrues in the reserve. The exchange rate between an aToken and its underlying asset is determined by the `supplyIndex`.
-   **Transferable:** As standard ERC20 tokens, aTokens can be freely transferred, effectively transferring the ownership of the underlying deposited asset and its future interest.

### 2.3 Interest Rate Model

The protocol uses a modular `InterestRateModel` to dynamically determine the supply and borrow interest rates for each reserve. The rates are a function of the **utilization rate** (`U`).

`U = Total Borrows / (Available Liquidity + Total Borrows)`

-   **Low Utilization:** Rates are low to encourage borrowing.
-   **High Utilization:** Rates increase sharply to encourage repayments and new deposits, ensuring liquidity is available for withdrawals.

The MVP uses a simple linear model (`DefaultInterestRateModel`), but the design allows for different models to be plugged in for different assets.

### 2.4 Price Oracles

Accurate asset valuation is critical for assessing collateral value and managing risk. The protocol uses Chainlink Price Feeds as its source of truth for asset prices.

-   **`ChainlinkOracleAdapter.sol`:** This contract serves as an intermediary. It fetches prices from the respective Chainlink aggregators and normalizes them to a common format (USD with 18 decimals) for consistent calculations within the `LendingPool`.

### 2.5 Health Factor & Liquidation

The **Health Factor (HF)** is a numerical representation of a user's borrowing position's safety.

`HF = (Total Value of Collateral in USD * Liquidation Threshold) / Total Value of Borrows in USD`

-   **`HF > 1`:** The position is safe. The user can borrow more or withdraw some collateral.
-   **`HF < 1`:** The position is under-collateralized and eligible for **liquidation**.

**Liquidation** is the process where a third-party (a liquidator) repays a portion of the borrower's debt in exchange for an equivalent amount of the borrower's collateral, plus a bonus.

-   **`LIQUIDATION_THRESHOLD` (e.g., 80%):** The percentage of collateral value that can be borrowed against.
-   **`LIQUIDATION_BONUS` (e.g., 5%):** The discount a liquidator receives on the seized collateral, acting as an incentive.
-   **`CLOSE_FACTOR` (e.g., 50%):** The maximum percentage of a user's debt that can be repaid in a single liquidation event. This prevents full liquidation and allows the borrower a chance to recover their position.

## 3. Contract Architecture

The system is composed of several modular contracts that interact with each other.

-   **`LendingPool.sol`:** The central hub and main entry point for all user interactions (`deposit`, `borrow`, `repay`, `liquidate`). It holds the application logic and state, orchestrating calls to other contracts.
-   **`aToken.sol`:** The ERC20-compliant interest-bearing token. Only the `LendingPool` (its `owner`) is authorized to mint or burn aTokens.
-   **`Reserve.sol`:** A data structure library defining the `Reserve.Data` struct. It is not a deployed contract but a way to organize reserve-specific data.
-   **`IInterestRateModel.sol` / `DefaultInterestRateModel.sol`:** The interface and a concrete implementation for calculating interest rates based on reserve utilization.
-   **`ChainlinkOracleAdapter.sol`:** An on-chain aggregator that provides normalized asset prices to the `LendingPool`.

## 4. Key User Flows

1.  **Deposit:**
    -   User calls `LendingPool.deposit(asset, amount)`.
    -   `LendingPool` transfers `amount` of `asset` from the user.
    -   `LendingPool` calculates the corresponding `aToken` amount to mint based on the current `supplyIndex`.
    -   `LendingPool` calls `aToken.mint(user, aTokenAmount)`.

2.  **Borrow:**
    -   User calls `LendingPool.borrow(asset, amount)`.
    -   The `LendingPool` calculates the user's Health Factor.
    -   If `HF` will remain above the threshold after borrowing, the transaction proceeds.
    -   The `LendingPool` transfers the `amount` of the borrowed `asset` to the user and updates their borrow balance.

3.  **Withdraw:**
    -   User calls `LendingPool.withdraw(asset, amount)`.
    -   The `LendingPool` calculates the `aToken` amount to burn based on the current `supplyIndex`.
    -   The `LendingPool` checks the user's Health Factor. The withdrawal is only permitted if the `HF` remains safe.
    -   `LendingPool` calls `aToken.burn(user, aTokenAmount)`.
    -   `LendingPool` transfers the `amount` of the `asset` back to the user.

## 5. Future Improvements (Stretch Goals)

-   **Variable/Stable Interest Rates:** Implement Aave's dual-rate mechanism.
-   **Flash Loans:** Allow for uncollateralized loans that are repaid within the same transaction.
-   **Gasless Approvals:** Implement EIP-2612 `permit` for a better user experience.
-   **Upgradeable Proxies:** Use a proxy pattern (like UUPS or Transparent) to allow for contract upgrades without data migration.
-   **Governance:** Add a governance module with a Timelock contract to manage protocol parameters like liquidation thresholds and interest rate models.