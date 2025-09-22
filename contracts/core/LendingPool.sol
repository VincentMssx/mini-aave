// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Reserve} from "./Reserve.sol";
import {aToken} from "../tokens/aToken.sol";
import {IInterestRateModel} from "../interest/InterestRateModel.sol";
import {ChainlinkOracleAdapter} from "../oracles/ChainlinkOracleAdapter.sol";

/**
 * @title LendingPool
 * @notice The main contract for the lending protocol, handling all user interactions.
 */
contract LendingPool is Ownable {
    using Reserve for Reserve.Data;

    // --- Events ---
    event Deposit(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);
    event Borrow(address indexed user, address indexed asset, uint256 amount);
    event Repay(address indexed user, address indexed asset, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed borrower, address repayAsset, address collateralAsset, uint256 repayAmount, uint256 seizedCollateralAmount);
    event ReserveInitialized(address indexed asset, address indexed aToken);
    event SetUserUseAsCollateral(address indexed user, address indexed asset, bool useAsCollateral);


    // --- State Variables ---
    mapping(address => Reserve.Data) private _reserves;
    address[] private _reservesList;
    mapping(address => mapping(address => uint256)) private _userBorrows; // asset -> user -> borrow amount
    mapping(address => mapping(address => bool)) private _userUsesAsCollateral; // user -> asset -> uses as collateral

    ChainlinkOracleAdapter public immutable oracle;

    // --- Constants ---
    uint256 public constant RAY = 1e27;
    uint256 public constant LIQUIDATION_THRESHOLD = 80 * 1e16; // 80%
    uint256 public constant LIQUIDATION_BONUS = 5 * 1e16; // 5%
    uint256 public constant CLOSE_FACTOR = 50 * 1e16; // 50%

    // --- Modifiers ---
    modifier reserveExists(address asset) {
        require(_reserves[asset].aTokenAddress != address(0), "LendingPool: Reserve does not exist");
        _;
    }

    // --- Constructor ---
    constructor(address oracleAddress) Ownable(msg.sender) {
        oracle = ChainlinkOracleAdapter(oracleAddress);
    }

    // --- Admin Functions ---
    function initReserve(address asset, address aTokenAddress, address interestRateModel) external onlyOwner {
        require(_reserves[asset].aTokenAddress == address(0), "LendingPool: Reserve already initialized");
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

    function setUserUseAsCollateral(address asset, bool useAsCollateral) external {
        _userUsesAsCollateral[msg.sender][asset] = useAsCollateral;
        emit SetUserUseAsCollateral(msg.sender, asset, useAsCollateral);
    }
    
    // --- Core Logic ---
    function deposit(address asset, uint256 amount) external reserveExists(asset) {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest(asset);
        
        Reserve.Data storage reserve = _reserves[asset];
        
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        uint256 aTokensToMint = (amount * RAY) / reserve.supplyIndex;
        aToken(reserve.aTokenAddress).mint(msg.sender, aTokensToMint);

        emit Deposit(msg.sender, asset, amount);
    }

    function withdraw(address asset, uint256 amount) external reserveExists(asset) {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest(asset);

        Reserve.Data storage reserve = _reserves[asset];
        uint256 aTokensToBurn = (amount * RAY) / reserve.supplyIndex;
        
        aToken aTokenContract = aToken(reserve.aTokenAddress);
        require(aTokenContract.balanceOf(msg.sender) >= aTokensToBurn, "Insufficient aToken balance");

        aTokenContract.burn(msg.sender, aTokensToBurn);
        
        // Health Factor check before withdrawing collateral
        if(_userUsesAsCollateral[msg.sender][asset]) {
            (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(msg.sender);
            require(totalDebtETH == 0 || (totalCollateralETH * 1e18) / totalDebtETH >= LIQUIDATION_THRESHOLD, "Cannot withdraw: health factor too low");
        }

        IERC20(asset).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount);
    }

    function borrow(address asset, uint256 amount) external reserveExists(asset) {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest(asset);

        (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(msg.sender);
        uint256 assetPrice = oracle.getAssetPrice(asset);
        uint256 newDebtETH = (amount * assetPrice) / 1e18;

        require(totalCollateralETH > 0, "No collateral available");
        require(((totalDebtETH + newDebtETH) * 1e18) / totalCollateralETH < LIQUIDATION_THRESHOLD, "Borrow would exceed collateral limits");

        Reserve.Data storage reserve = _reserves[asset];
        _userBorrows[asset][msg.sender] += amount;
        reserve.totalBorrows += amount;

        IERC20(asset).transfer(msg.sender, amount);
        emit Borrow(msg.sender, asset, amount);
    }

    function repay(address asset, uint256 amount) external reserveExists(asset) {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest(asset);

        uint256 userDebt = _userBorrows[asset][msg.sender];
        uint256 amountToRepay = amount > userDebt ? userDebt : amount;

        IERC20(asset).transferFrom(msg.sender, address(this), amountToRepay);

        Reserve.Data storage reserve = _reserves[asset];
        _userBorrows[asset][msg.sender] -= amountToRepay;
        reserve.totalBorrows -= amountToRepay;

        emit Repay(msg.sender, asset, amountToRepay);
    }
    
    function liquidate(address borrower, address repayAsset, address collateralAsset) external payable {
        _accrueInterest(repayAsset);
        _accrueInterest(collateralAsset);

        (uint256 totalCollateralETH, uint256 totalDebtETH) = _getUserAccountData(borrower);
        uint256 healthFactor = (totalCollateralETH * 1e18) / totalDebtETH;
        require(healthFactor < 1e18, "Borrower is not under liquidation threshold");
        
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
        
        aToken(collateralReserve.aTokenAddress).burn(borrower, aTokensToSeize);
        aToken(collateralReserve.aTokenAddress).mint(msg.sender, aTokensToSeize);

        IERC20(repayAsset).transferFrom(msg.sender, address(this), repayAmount);

        emit Liquidate(msg.sender, borrower, repayAsset, collateralAsset, repayAmount, seizedCollateralAmount);
    }

    // --- Internal & View Functions ---
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

    function _getUserAccountData(address user) internal view returns (uint256 totalCollateralETH, uint256 totalDebtETH) {
        for (uint256 i = 0; i < _reservesList.length; i++) {
            address asset = _reservesList[i];
            Reserve.Data storage reserve = _reserves[asset];

            if (_userUsesAsCollateral[user][asset]) {
                uint256 aTokenBalance = aToken(reserve.aTokenAddress).balanceOf(user);
                uint256 balance = (aTokenBalance * reserve.supplyIndex) / RAY;
                totalCollateralETH += (balance * oracle.getAssetPrice(asset)) / 1e18;
            }

            if (_userBorrows[asset][user] > 0) {
                totalDebtETH += (_userBorrows[asset][user] * oracle.getAssetPrice(asset)) / 1e18;
            }
        }
    }

    function getReservesList() external view returns (address[] memory) {
        return _reservesList;
    }
}