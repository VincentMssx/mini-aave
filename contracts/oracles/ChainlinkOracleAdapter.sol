// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Thrown when a price feed is not set for an asset.
 */
error PriceFeedNotSet();
/**
 * @notice Thrown when the price returned from the oracle is invalid.
 */
error InvalidPrice();

/**
 * @title ChainlinkOracleAdapter
 * @author Vincent Mousseaux
 * @notice Provides a standardized interface for fetching asset prices from Chainlink.
 * @dev Normalizes prices to 18 decimals.
 */
contract ChainlinkOracleAdapter is Ownable {
    mapping(address => address) private _assetToFeed;
    /**
     * @notice The number of decimals for the price returned by this oracle.
     */
    uint8 public constant PRICE_DECIMALS = 18;

    /**
     * @notice Emitted when the price feed for an asset is updated.
     * @param asset The address of the asset.
     * @param feed The address of the new price feed.
     */
    event AssetFeedUpdated(address indexed asset, address indexed feed);

    /**
     * @notice Constructs the ChainlinkOracleAdapter contract.
     * @param owner The owner of the contract.
     */
    constructor(address owner) public Ownable(owner) {}

    /**
     * @notice Sets the Chainlink aggregator feed for a given asset.
     * @param asset The address of the asset.
     * @param feed The address of the Chainlink price feed aggregator.
     */
    function setAssetFeed(address asset, address feed) external onlyOwner {
        _assetToFeed[asset] = feed;
        emit AssetFeedUpdated(asset, feed);
    }

    /**
     * @notice Gets the price of an asset in USD, normalized to 18 decimals.
     * @param asset The address of the asset.
     * @return The price of the asset.
     */
    function getAssetPrice(address asset) external view returns (uint256) {
        address feedAddress = _assetToFeed[asset];
        if (feedAddress == address(0)) revert PriceFeedNotSet();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();

        if (price <= 0) revert InvalidPrice();

        uint8 feedDecimals = priceFeed.decimals();
        if (feedDecimals >= PRICE_DECIMALS) {
            return uint256(price) / (10 ** (feedDecimals - PRICE_DECIMALS));
        } else {
            return uint256(price) * (10 ** (PRICE_DECIMALS - feedDecimals));
        }
    }

    /**
     * @notice Gets the address of the price feed for a given asset.
     * @param asset The address of the asset.
     * @return The address of the price feed.
     */
    function getAssetFeed(address asset) external view returns(address) {
        return _assetToFeed[asset];
    }
}