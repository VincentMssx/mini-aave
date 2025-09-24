// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @author Vincent Mousseaux
 * @notice A mock for the Chainlink V3 Aggregator, for testing purposes.
 */
contract MockV3Aggregator is AggregatorV3Interface {
    /**
     * @notice The number of decimals for the price feed.
     */
    uint8 public constant DECIMALS = 8;
    /**
     * @notice The latest answer from the price feed.
     */
    int256 private latestAnswer;

    /**
     * @notice Constructs the MockV3Aggregator contract.
     * @param _initialAnswer The initial answer for the price feed.
     */
    constructor(int256 _initialAnswer) public {
        latestAnswer = _initialAnswer;
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function getRoundData(uint80)
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (1, latestAnswer, block.timestamp, block.timestamp, 1);
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (1, latestAnswer, block.timestamp, block.timestamp, 1);
    }

    /**
     * @notice Sets the latest answer for the price feed.
     * @param _newAnswer The new answer to set.
     */
    function setLatestAnswer(int256 _newAnswer) external {
        latestAnswer = _newAnswer;
    }
}