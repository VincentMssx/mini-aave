// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice A mock ERC20 token for testing purposes.
 */
contract MockERC20 is ERC20 {
    /**
     * @notice Constructs the MockERC20 contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param decimals_ The number of decimals of the token.
     */
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _setupDecimals(decimals_);
    }

    /**
     * @notice Sets the number of decimals for the token.
     * @dev This is a workaround for compatibility between OpenZeppelin 4.x and 5.x.
     * @param decimals_ The number of decimals.
     */
    function _setupDecimals(uint8 decimals_) internal {
        // an internal function in OZ 4.x, but not in 5.x.
        // This is a workaround to maintain compatibility.
    }

    /**
     * @notice Mints new tokens to a specified address.
     * @param to The address to mint the tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}