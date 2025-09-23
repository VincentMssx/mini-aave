// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Reserve} from "./Reserve.sol";
import {AToken} from "../tokens/AToken.sol";
import {IInterestRateModel} from "../interest/InterestRateModel.sol";
import {ChainlinkOracleAdapter} from "../oracles/ChainlinkOracleAdapter.sol";

// --- Custom Errors ---
/**
 * @notice Thrown when an operation is attempted on a non-existent reserve.
 */
error ReserveDoesNotExist();
/**
 * @notice Thrown when trying to initialize a reserve that has already been initialized.
 */
error ReserveAlreadyInitialized();
/**
 * @notice Thrown when an operation is attempted with an amount of 0.
 */
error AmountIsZero();
/**
 * @notice Thrown when a user has an insufficient aToken balance for a withdrawal.
 */
error InsufficientATokenBalance();
/**
 * @notice Thrown when a withdrawal would lower the user's health factor below the liquidation threshold.
 */
error HealthFactorTooLow();
/**
 * @notice Thrown when a user with no collateral attempts to borrow.
 */
error NoCollateralAvailable();
/**
 * @notice Thrown when a borrow action would exceed the user's collateral limits.
 */
error BorrowExceedsCollateralLimits();
/**
 * @notice Thrown when a liquidation is attempted on a borrower who is not under the liquidation threshold.
 */
error BorrowerNotUnderLiquidationThreshold();

/**
 * @title LendingPool
 * @author Vincent Mousseaux
 * @notice The main contract for the lending protocol, handling all user interactions.
 */
contract LendingPool is Ownable {
    using Reserve for Reserve.Data;

    // --- Events ---
    /**
     * @notice Emitted when a user deposits an asset into the lending pool.
     * @param user The address of the user who deposited.
     * @param asset The address of the asset deposited.
     * @param amount The amount of the asset deposited.
     */
    event Deposit(address indexed user, address indexed asset, uint256 indexed amount);
    /**
     * @notice Emitted when a user withdraws an asset from the lending pool.
     * @param user The address of the user who withdrew.
     * @param asset The address of the asset withdrawn.
     * @param amount The amount of the asset withdrawn.
     */
    event Withdraw(address indexed user, address indexed asset, uint256 indexed amount);
    /**
     * @notice Emitted when a user borrows an asset from the lending pool.
     * @param user The address of the user who borrowed.
     * @param asset The address of the asset borrowed.
     * @param amount The amount of the asset borrowed.
     */
    event Borrow(address indexed user, address indexed asset, uint256 indexed amount);
    /**
     * @notice Emitted when a user repays a borrowed asset to the lending pool.
     * @param user The address of the user who repaid.
     * @param asset The address of the asset repaid.
     * @param amount The amount of the asset repaid.
     */
    event Repay(address indexed user, address indexed asset, uint256 indexed amount);
    /**
     * @notice Emitted when a borrower's position is liquidated.
     * @param liquidator The address of the user who performed the liquidation.
     * @param borrower The address of the user whose position was liquidated.
     * @param repayAsset The address of the asset that was repaid to cover the debt.
     * @param collateralAsset The address of the collateral asset that was seized.
     * @param repayAmount The amount of the repaid asset.
     * @param seizedCollateralAmount The amount of the seized collateral.
     */
    event Liquidate(address indexed liquidator, address indexed borrower, address indexed repayAsset, address collateralAsset, uint256 repayAmount, uint256 seizedCollateralAmount);
    /**
     * @notice Emitted when a new reserve is initialized.
     * @param asset The address of the underlying asset.
     * @param aToken The address of the corresponding aToken.
     */
    event ReserveInitialized(address indexed asset, address indexed aToken);
    /**
     * @notice Emitted when a user enables or disables an asset to be used as collateral.
     * @param user The address of the user.
     * @param asset The address of the asset.
     * @param useAsCollateral True if the asset is enabled as collateral, false otherwise.
     */
    event SetUserUseAsCollateral(address indexed user, address indexed asset, bool indexed useAsCollateral);


    // --- State Variables ---
    mapping(address => Reserve.Data) private _reserves;
    address[] private _reservesList;
    mapping(address => mapping(address => uint256)) private _userBorrows; // asset -> user -> borrow amount
    mapping(address => mapping(address => bool)) private _userUsesAsCollateral; // user -> asset -> uses as collateral

    /**
     * @notice The address of the Chainlink oracle adapter.
     */
    ChainlinkOracleAdapter public immutable oracle;

    // --- Constants ---
    /**
     * @notice A constant for high-precision arithmetic, equal to 10^27.
     */
    uint256 public constant RAY = 1e27;
    /**
     * @notice The threshold at which a position is considered undercollateralized and can be liquidated.
     */
    uint256 public constant LIQUIDATION_THRESHOLD = 80 * 1e16; // 80%
    /**
     * @notice The bonus percentage given to liquidators.
     */
    uint256 public constant LIQUIDATION_BONUS = 5 * 1e16; // 5%
    /**
     * @notice The percentage of a position that can be liquidated at once.
     */
    uint256 public constant CLOSE_FACTOR = 50 * 1e16; // 50%

    // --- Modifiers ---
    /**
     * @notice A modifier to check if a reserve exists for a given asset.
     * @param asset The address of the asset to check.
     */
    modifier reserveExists(address asset) {
        if (_reserves[asset].aTokenAddress == address(0)) revert ReserveDoesNotExist();
        _;
    }

    // --- Constructor ---
    /**
     * @notice Constructs the LendingPool contract.
     * @param oracleAddress The address of the Chainlink oracle adapter.
     */
    constructor(address oracleAddress) Ownable(msg.sender) {
        oracle = ChainlinkOracleAdapter(oracleAddress);
    }

    // --- Admin Functions ---
    /**
     * @notice Initializes a new reserve.
     * @param asset The address of the underlying asset.
     * @param aTokenAddress The address of the corresponding aToken.
     * @param interestRateModel The address of the interest rate model.
     */
    function initReserve(address asset, address aTokenAddress, address interestRateModel) external onlyOwner {
        if (_reserves[asset].aTokenAddress != address(0)) revert ReserveAlreadyInitialized();
        _reserves[asset] = Reserve.Data({
            aTokenAddress: aTokenAddress,
            interestRateModelAddress: interestRateModel,
            supplyIndex: RAY,
            borrowIndex: RAY,
            lastUpdateTimestamp: uint40(block.timestamp),
            totalBorrows: 0
        });
        _reservesList.push(asset);
        emit ReserveInitialized(asset, aTokenAddress);
    }

    /**
     * @notice Sets whether a user can use an asset as collateral.
     * @param asset The address of the asset.
     * @param useAsCollateral True if the asset can be used as collateral, false otherwise.
     */
    function setUserUseAsCollateral(address asset, bool useAsCollateral) external {
        _userUsesAsCollateral[msg.sender][asset] = useAsCollateral;
        emit SetUserUseAsCollateral(msg.sender, asset, useAsCollateral);
    }
    
    // --- Core Logic ---
    /**
     * @notice Deposits an asset into the lending pool.
     * @param asset The address of the asset to deposit.
     * @param amount The amount to deposit.
     */
    function deposit(address asset, uint256 amount) external reserveExists(asset) {
        if (amount == 0) revert AmountIsZero();
        _accrueInterest(asset);
        
        Reserve.Data storage reserve = _reserves[asset];
        
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        uint256 aTokensToMint = (amount * RAY) / reserve.supplyIndex;
        AToken(reserve.aTokenAddress).mint(msg.sender, aTokensToMint);

        emit Deposit(msg.sender, asset, amount);
    }

    /**
     * @notice Withdraws an asset from the lending pool.
     * @param asset The address of the asset to withdraw.
     * @param amount The amount to withdraw.
     */
    function withdraw(address asset, uint256 amount) external reserveExists(asset) {
        if (amount == 0) revert AmountIsZero();
        _accrueInterest(asset);

        Reserve.Data storage reserve = _reserves[asset];
        uint256 aTokensToBurn = (amount * RAY) / reserve.supplyIndex;
        
        AToken aTokenContract = AToken(reserve.aTokenAddress);
        if (aTokenContract.balanceOf(msg.sender) < aTokensToBurn) revert InsufficientATokenBalance();

        aTokenContract.burn(msg.sender, aTokensToBurn);
        
        // Health Factor check before withdrawing collateral
        if(_userUsesAsCollateral[msg.sender][asset]) {
            (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(msg.sender);
            if (totalDebtETH > 0 && (totalCollateralETH * 1e18) / totalDebtETH < LIQUIDATION_THRESHOLD) revert HealthFactorTooLow();
        }

        IERC20(asset).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount);
    }

    /**
     * @notice Borrows an asset from the lending pool.
     * @param asset The address of the asset to borrow.
     * @param amount The amount to borrow.
     */
    function borrow(address asset, uint256 amount) external reserveExists(asset) {
        if (amount == 0) revert AmountIsZero();
        _accrueInterest(asset);

        (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(msg.sender);
        uint256 assetPrice = oracle.getAssetPrice(asset);
        uint256 newDebtETH = (amount * assetPrice) / 1e18;

        if (totalCollateralETH == 0) revert NoCollateralAvailable();
        if (((totalDebtETH + newDebtETH) * 1e18) / totalCollateralETH >= LIQUIDATION_THRESHOLD) revert BorrowExceedsCollateralLimits();

        Reserve.Data storage reserve = _reserves[asset];
        _userBorrows[asset][msg.sender] += amount;
        reserve.totalBorrows += amount;

        IERC20(asset).transfer(msg.sender, amount);
        emit Borrow(msg.sender, asset, amount);
    }

    /**
     * @notice Repays a borrowed asset to the lending pool.
     * @param asset The address of the asset to repay.
     * @param amount The amount to repay.
     */
    function repay(address asset, uint256 amount) external reserveExists(asset) {
        if (amount == 0) revert AmountIsZero();
        _accrueInterest(asset);

        uint256 userDebt = _userBorrows[asset][msg.sender];
        uint256 amountToRepay = amount > userDebt ? userDebt : amount;

        IERC20(asset).transferFrom(msg.sender, address(this), amountToRepay);

        Reserve.Data storage reserve = _reserves[asset];
        _userBorrows[asset][msg.sender] -= amountToRepay;
        reserve.totalBorrows -= amountToRepay;

        emit Repay(msg.sender, asset, amountToRepay);
    }
    
    /**
     * @notice Liquidates a borrower's position.
     * @param borrower The address of the borrower to liquidate.
     * @param repayAsset The address of the asset to repay.
     * @param collateralAsset The address of the collateral asset to seize.
     */
    function liquidate(address borrower, address repayAsset, address collateralAsset) external payable {
        _accrueInterest(repayAsset);
        _accrueInterest(collateralAsset);

        (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(borrower);
        uint256 healthFactor = (totalCollateralETH * 1e18) / totalDebtETH;
        if (healthFactor >= 1e18) revert BorrowerNotUnderLiquidationThreshold();
        
        uint256 userDebt = _userBorrows[repayAsset][borrower];
        uint256 repayAmount = (userDebt * CLOSE_FACTOR) / 1e18;
        
        uint256 repayAssetPrice = oracle.getAssetPrice(repayAsset);
        uint256 collateralAssetPrice = oracle.getAssetPrice(collateralAsset);
        
        uint256 repayValueInETH = (repayAmount * repayAssetPrice) / 1e18;
        uint256 seizedCollateralValueInETH = (repayValueInETH * (1e18 + LIQUIDATION_BONUS)) / 1e18;
        uint256 seizedCollateralAmount = (seizedCollateralValueInETH * 1e18) / collateralAssetPrice;

        Reserve.Data storage repayReserve = _reserves[repayAsset];
        repayReserve.totalBorrows -= repayAmount;
        _userBorrows[repayAsset][borrower] -= repayAmount;
        
        Reserve.Data storage collateralReserve = _reserves[collateralAsset];
        uint256 aTokensToSeize = (seizedCollateralAmount * RAY) / collateralReserve.supplyIndex;
        
        AToken(collateralReserve.aTokenAddress).burn(borrower, aTokensToSeize);
        AToken(collateralReserve.aTokenAddress).mint(msg.sender, aTokensToSeize);

        IERC20(repayAsset).transferFrom(msg.sender, address(this), repayAmount);

        emit Liquidate(msg.sender, borrower, repayAsset, collateralAsset, repayAmount, seizedCollateralAmount);
    }

    // --- Internal & View Functions ---
    /**
     * @notice Accrues interest on a reserve.
     * @param asset The address of the asset to accrue interest on.
     */
    function _accrueInterest(address asset) internal {
        Reserve.Data storage reserve = _reserves[asset];
        uint40 lastTimestamp = reserve.lastUpdateTimestamp;

        if (block.timestamp == lastTimestamp) {
            return;
        }

        uint256 timeDelta = block.timestamp - lastTimestamp;
        
        IInterestRateModel model = IInterestRateModel(reserve.interestRateModelAddress);
        uint256 availableLiquidity = IERC20(asset).balanceOf(address(this)) - reserve.totalBorrows;

        (uint256 borrowRate, uint256 supplyRate) = model.calculateInterestRates(availableLiquidity, reserve.totalBorrows);
        
        // Compound interest
        uint256 supplyInterest = ((supplyRate * timeDelta) * reserve.supplyIndex) / RAY;
        reserve.supplyIndex += supplyInterest;

        uint256 borrowInterest = ((borrowRate * timeDelta) * reserve.borrowIndex) / RAY;
        reserve.borrowIndex += borrowInterest;

        // Note: In a real system, totalBorrows would also be updated based on the borrow index.
        // For this MVP, we simplify and update it directly in borrow/repay for clarity.
        
        reserve.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /**
     * @notice Gets a user's account data.
     * @param user The address of the user.
     * @return totalCollateralETH The total value of the user's collateral in ETH.
     * @return totalDebtETH The total value of the user's debt in ETH.
     */
    function _getUserAccountData(address user) internal view returns (uint256 totalCollateralETH, uint256 totalDebtETH) {
        for (uint256 i = 0; i < _reservesList.length; ++i) {
            address asset = _reservesList[i];
            Reserve.Data storage reserve = _reserves[asset];

            if (_userUsesAsCollateral[user][asset]) {
                uint256 aTokenBalance = AToken(reserve.aTokenAddress).balanceOf(user);
                uint256 balance = (aTokenBalance * reserve.supplyIndex) / RAY;
                totalCollateralETH += (balance * oracle.getAssetPrice(asset)) / 1e18;
            }

            if (_userBorrows[asset][user] != 0) {
                totalDebtETH += (_userBorrows[asset][user] * oracle.getAssetPrice(asset)) / 1e18;
            }
        }
    }

    /**
     * @notice Gets the list of reserves.
     * @return The list of reserve addresses.
     */
    function getReservesList() external view returns (address[] memory) {
        return _reservesList;
    }
}