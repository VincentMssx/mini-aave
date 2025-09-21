// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title aToken
 * @notice An interest-bearing token that represents a deposit in the LendingPool.
 * @dev This is a standard ERC20 token with minting and burning restricted to the owner (the LendingPool).
 */
contract aToken is ERC20, Ownable {
    // The address of the underlying asset for this aToken
    address public immutable UNDERLYING_ASSET;

    constructor(
        address underlyingAsset,
        address pool,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) Ownable(pool) {
        UNDERLYING_ASSET = underlyingAsset;
    }

    /**
     * @dev Mints aTokens to a user's account.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     * @notice This function can only be called by the LendingPool.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns aTokens from a user's account.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     * @notice This function can only be called by the LendingPool.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}