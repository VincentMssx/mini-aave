// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Reserve
 * @notice Library to store the data for each asset reserve.
 */
library Reserve {
    /**
     * @notice A RAY is a high-precision number (1e27) used for interest rate calculations
     */
    uint256 public constant RAY = 1e27;

    struct Data {
        /**
         * @notice Address of the associated aToken
         */
        address aTokenAddress;
        /**
         * @notice Address of the interest rate model
         */
        address interestRateModelAddress;
        /**
         * @notice The cumulative index for supply interest, in RAY
         */
        uint256 supplyIndex;
        /**
         * @notice The cumulative index for borrow interest, in RAY
         */
        uint256 borrowIndex;
        /**
         * @notice Timestamp of the last interest accrual
         */
        uint40 lastUpdateTimestamp;
        /**
         * @notice Total principal amount borrowed from this reserve
         */
        uint256 totalBorrows;
    }
}