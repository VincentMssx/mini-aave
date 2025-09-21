import { ethers } from "hardhat";
import { expect } from "chai";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { LendingPool, MockERC20, aToken, MockV3Aggregator, DefaultInterestRateModel } from "../typechain-types";
import { ChainlinkOracleAdapter } from "../typechain-types";

describe("LendingPool", function () {
    let deployer: HardhatEthersSigner, user1: HardhatEthersSigner, user2: HardhatEthersSigner;
    let lendingPool: LendingPool;
    let weth: MockERC20, dai: MockERC20;
    let aWeth: aToken, aDai: aToken;
    let oracle: ChainlinkOracleAdapter;
    let interestRateModel: DefaultInterestRateModel;

    const WETH_PRICE = ethers.parseUnits("3000", 8); // $3000 with 8 decimals
    const DAI_PRICE = ethers.parseUnits("1", 8); // $1 with 8 decimals
    
    // Amounts
    const DEPOSIT_AMOUNT_WETH = ethers.parseEther("10"); // 10 WETH
    const DEPOSIT_AMOUNT_DAI = ethers.parseEther("5000"); // 5000 DAI

    beforeEach(async function () {
        [deployer, user1, user2] = await ethers.getSigners();

        // Deploy Mocks
        const MockERC20Factory = await ethers.getContractFactory("MockERC20");
        weth = await MockERC20Factory.deploy("Wrapped Ether", "WETH", 18);
        dai = await MockERC20Factory.deploy("Dai Stablecoin", "DAI", 18);

        const MockV3AggregatorFactory = await ethers.getContractFactory("MockV3Aggregator");
        const ethUsdPriceFeed = await MockV3AggregatorFactory.deploy(WETH_PRICE);
        const daiUsdPriceFeed = await MockV3AggregatorFactory.deploy(DAI_PRICE);

        // Deploy Core Contracts
        const OracleFactory = await ethers.getContractFactory("ChainlinkOracleAdapter");
        oracle = await OracleFactory.deploy(deployer.address);
        await oracle.setAssetFeed(await weth.getAddress(), await ethUsdPriceFeed.getAddress());
        await oracle.setAssetFeed(await dai.getAddress(), await daiUsdPriceFeed.getAddress());

        const IRMFactory = await ethers.getContractFactory("DefaultInterestRateModel");
        interestRateModel = await IRMFactory.deploy();

        const LendingPoolFactory = await ethers.getContractFactory("LendingPool");
        lendingPool = await LendingPoolFactory.deploy(await oracle.getAddress());
        
        // Deploy aTokens
        const ATokenFactory = await ethers.getContractFactory("aToken");
        aWeth = await ATokenFactory.deploy(await weth.getAddress(), await lendingPool.getAddress(), "aWETH", "aWETH");
        aDai = await ATokenFactory.deploy(await dai.getAddress(), await lendingPool.getAddress(), "aDAI", "aDAI");

        // Initialize Reserves
        await lendingPool.initReserve(await weth.getAddress(), await aWeth.getAddress(), await interestRateModel.getAddress());
        await lendingPool.initReserve(await dai.getAddress(), await aDai.getAddress(), await interestRateModel.getAddress());
        
        // Fund users and approve lending pool
        await weth.mint(user1.address, DEPOSIT_AMOUNT_WETH);
        await dai.mint(user2.address, DEPOSIT_AMOUNT_DAI);

        await weth.connect(user1).approve(await lendingPool.getAddress(), DEPOSIT_AMOUNT_WETH);
        await dai.connect(user2).approve(await lendingPool.getAddress(), DEPOSIT_AMOUNT_DAI);
    });

    describe("Deposit", function () {
        it("should allow a user to deposit assets and receive aTokens", async function () {
            await lendingPool.connect(user1).deposit(await weth.getAddress(), DEPOSIT_AMOUNT_WETH);
            
            expect(await weth.balanceOf(user1.address)).to.equal(0);
            expect(await aWeth.balanceOf(user1.address)).to.equal(DEPOSIT_AMOUNT_WETH); // 1:1 minting initially
            expect(await weth.balanceOf(await lendingPool.getAddress())).to.equal(DEPOSIT_AMOUNT_WETH);
        });

        it("should revert if depositing zero amount", async function () {
            await expect(lendingPool.connect(user1).deposit(await weth.getAddress(), 0))
                .to.be.revertedWith("Amount must be > 0");
        });
    });

    describe("Withdraw", function () {
        beforeEach(async function () {
            await lendingPool.connect(user1).deposit(await weth.getAddress(), DEPOSIT_AMOUNT_WETH);
        });

        it("should allow a user to withdraw their assets", async function () {
            const withdrawAmount = ethers.parseEther("5");
            await lendingPool.connect(user1).withdraw(await weth.getAddress(), withdrawAmount);

            expect(await weth.balanceOf(user1.address)).to.equal(withdrawAmount);
            expect(await aWeth.balanceOf(user1.address)).to.equal(DEPOSIT_AMOUNT_WETH - withdrawAmount);
        });

        it("should revert if trying to withdraw more than deposited", async function () {
             await expect(lendingPool.connect(user1).withdraw(await weth.getAddress(), DEPOSIT_AMOUNT_WETH + ethers.parseEther("1")))
                .to.be.revertedWith("Insufficient aToken balance");
        });
    });

    describe("Borrow", function () {
        beforeEach(async function () {
            // user1 deposits 10 WETH as collateral
            await lendingPool.connect(user1).deposit(await weth.getAddress(), DEPOSIT_AMOUNT_WETH);
            await lendingPool.connect(user1).setUserUseAsCollateral(await weth.getAddress(), true);
            // user2 deposits 5000 DAI to be borrowed
            await lendingPool.connect(user2).deposit(await dai.getAddress(), DEPOSIT_AMOUNT_DAI);
        });

        it("should allow a user to borrow an asset against their collateral", async function () {
            const borrowAmount = ethers.parseEther("1000"); // Borrow 1000 DAI
            await lendingPool.connect(user1).borrow(await dai.getAddress(), borrowAmount);

            expect(await dai.balanceOf(user1.address)).to.equal(borrowAmount);
        });

        it("should revert if borrow amount exceeds collateral limit", async function () {
            // 10 WETH collateral = $30,000. Liquidation threshold is 80%.
            // Max borrow = $30,000 * 0.80 = $24,000
            const borrowAmount = ethers.parseEther("24001");
            
            await expect(lendingPool.connect(user1).borrow(await dai.getAddress(), borrowAmount))
                .to.be.revertedWith("Borrow would exceed collateral limits");
        });

        it("should revert if user has no collateral", async function () {
             await expect(lendingPool.connect(user2).borrow(await weth.getAddress(), ethers.parseEther("1")))
                .to.be.revertedWith("No collateral available");
        });
    });
    
    describe("Repay", function () {
        let borrowAmount: bigint;

        beforeEach(async function () {
            await lendingPool.connect(user1).deposit(await weth.getAddress(), DEPOSIT_AMOUNT_WETH);
            await lendingPool.connect(user1).setUserUseAsCollateral(await weth.getAddress(), true);
            await lendingPool.connect(user2).deposit(await dai.getAddress(), DEPOSIT_AMOUNT_DAI);
            
            borrowAmount = ethers.parseEther("1000");
            await lendingPool.connect(user1).borrow(await dai.getAddress(), borrowAmount);
            await dai.connect(deployer).mint(user1.address, borrowAmount); // Give user1 DAI to repay
            await dai.connect(user1).approve(await lendingPool.getAddress(), borrowAmount);
        });

        it("should allow a user to repay their debt", async function () {
            const initialDaiBalance = await dai.balanceOf(user1.address);
            await lendingPool.connect(user1).repay(await dai.getAddress(), borrowAmount);
            
            const finalDaiBalance = await dai.balanceOf(user1.address);
            expect(initialDaiBalance - finalDaiBalance).to.equal(borrowAmount);
        });
    });

    describe("Liquidation", function () {
        let ethUsdPriceFeed: MockV3Aggregator;
        beforeEach(async function () {
            ethUsdPriceFeed = await ethers.getContractFactory("MockV3Aggregator").then(f => f.deploy(WETH_PRICE));
            await oracle.setAssetFeed(await weth.getAddress(), await ethUsdPriceFeed.getAddress());
            // user1 deposits 1 WETH as collateral
            await weth.mint(user1.address, ethers.parseEther("1"));
            await weth.connect(user1).approve(await lendingPool.getAddress(), ethers.parseEther("1"));
            await lendingPool.connect(user1).deposit(await weth.getAddress(), ethers.parseEther("1"));
            await lendingPool.connect(user1).setUserUseAsCollateral(await weth.getAddress(), true);
            
            // user2 deposits DAI for liquidity
            await lendingPool.connect(user2).deposit(await dai.getAddress(), DEPOSIT_AMOUNT_DAI);

            // user1 borrows DAI. 1 WETH = $3000. Max borrow = $2400. Let's borrow $2300
            await lendingPool.connect(user1).borrow(await dai.getAddress(), ethers.parseEther("2300"));
        });
        
        it("should allow a liquidator to liquidate an unhealthy position", async function () {
            // WETH price drops, making the position unhealthy.
            await ethUsdPriceFeed.setLatestAnswer(ethers.parseUnits("2000", 8));
            
            const liquidator = user2;
            const amountToRepay = ethers.parseEther("1150"); // 50% of 2300 (close factor)
            
            // Liquidator needs DAI to repay the debt
            await dai.mint(liquidator.address, amountToRepay);
            await dai.connect(liquidator).approve(await lendingPool.getAddress(), amountToRepay);

            const initialLiquidatorATokenBalance = await aWeth.balanceOf(liquidator.address);
            
            await lendingPool.connect(liquidator).liquidate(user1.address, await dai.getAddress(), await weth.getAddress());

            // Check liquidator received collateral with bonus
            // Repaid value = $1150. Bonus = 5%. Seized value = 1150 * 1.05 = $1207.5
            // Seized WETH = 1207.5 / 2000 (new price) = ~0.60375 WETH
            const expectedSeizedWeth = ethers.parseEther("0.60375");
            const finalLiquidatorATokenBalance = await aWeth.balanceOf(liquidator.address);
            
            // Check if seized amount is close to expected
            expect(finalLiquidatorATokenBalance - initialLiquidatorATokenBalance).to.be.closeTo(expectedSeizedWeth, ethers.parseEther("0.0001"));

            // Check borrower's debt was reduced
            // This requires getting the borrow balance from the contract, which is not exposed in the provided ABI.
            // We can infer it was reduced because the call succeeded. A full test would check this state.
        });

        it("should revert if position is not eligible for liquidation", async function () {
            await expect(lendingPool.connect(user2).liquidate(user1.address, await dai.getAddress(), await weth.getAddress()))
                .to.be.revertedWith("Borrower is not under liquidation threshold");
        });
    });
});