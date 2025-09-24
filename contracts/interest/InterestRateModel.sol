// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInterestRateModel
 * @author Vincent Mousseaux
 * @notice Interface for an interest rate model.
 */
interface IInterestRateModel {
    /**
     * @notice Calculates the current borrow and supply interest rates.
     * @param availableLiquidity The amount of liquidity available in the reserve.
     * @param totalBorrows The total amount borrowed from the reserve.
     * @return The borrow interest rate per second, in RAY (1e27).
     * @return The supply interest rate per second, in RAY (1e27).
     */
    function calculateInterestRates(
        uint256 availableLiquidity,
        uint256 totalBorrows
    ) external view returns (uint256, uint256);
}

/**
 * @title DefaultInterestRateModel
 * @author Vincent Mousseaux
 * @notice A simple linear interest rate model.
 * @dev The interest rate is a function of the utilization rate (totalBorrows / (totalBorrows + availableLiquidity)).
 * Rates are expressed in RAY (1e27).
 */
contract DefaultInterestRateModel is IInterestRateModel {
    /**
     * @notice The number of seconds in a year.
     */
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    /**
     * @notice A RAY is a high-precision number (1e27) used for interest rate calculations.
     */
    uint256 public constant RAY = 1e27;

    /**
     * @notice The base interest rate (APR), scaled by 1e18.
     */
    uint256 private constant BASE_RATE = 0.02 * 1e18; // 2%
    /**
     * @notice The slope of the interest rate curve (APR), scaled by 1e18.
     */
    uint256 private constant SLOPE_1 = 0.18 * 1e18; // 18%

    /**
     * @inheritdoc IInterestRateModel
     */
    function calculateInterestRates(
        uint256 availableLiquidity,
        uint256 totalBorrows
    ) external pure override returns (uint256 borrowRate, uint256 supplyRate) {
        if (totalBorrows == 0) {
            return (0, 0);
        }

        uint256 totalLiquidity = availableLiquidity + totalBorrows;
        uint256 utilizationRate = (totalBorrows * 1e18) / totalLiquidity;

        // Borrow rate (APR) is calculated based on utilization
        uint256 borrowApr = BASE_RATE + ((utilizationRate * SLOPE_1) / 1e18);

        // Supply rate is derived from borrow rate and utilization
        uint256 supplyApr = (borrowApr * utilizationRate) / 1e18;

        // Convert APR to rate per second in RAY
        borrowRate = (borrowApr * RAY / 1e18) / SECONDS_PER_YEAR;
        supplyRate = (supplyApr * RAY / 1e18) / SECONDS_PER_YEAR;
    }
}