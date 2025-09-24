// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AToken
 * @author Vincent Mousseaux
 * @notice An interest-bearing token that represents a deposit in the LendingPool.
 * @dev This is a standard ERC20 token with minting and burning restricted to the owner (the LendingPool).
 */
contract AToken is ERC20, Ownable {
    /**
     * @notice The address of the underlying asset for this aToken.
     */
    address public immutable UNDERLYING_ASSET;

    /**
     * @notice Constructs the AToken contract.
     * @param underlyingAsset The address of the underlying asset.
     * @param pool The address of the LendingPool.
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     */
    constructor(
        address underlyingAsset,
        address pool,
        string memory tokenName,
        string memory tokenSymbol
    ) public ERC20(tokenName, tokenSymbol) Ownable(pool) {
        UNDERLYING_ASSET = underlyingAsset;
    }

    /**
     * @dev Mints ATokens to a user's account.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     * @notice This function can only be called by the LendingPool.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns ATokens from a user's account.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     * @notice This function can only be called by the LendingPool.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}