import { ethers } from "hardhat";
import { MockERC20, aToken, LendingPool } from "../typechain-types";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Interacting with contracts with the account:", deployer.address);

  // --- 1. Deploy Contracts (same as deploy.ts) ---
  console.log("\n--- Deploying Contracts ---");
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const weth: MockERC20 = await MockERC20Factory.deploy("Wrapped Ether", "WETH", 18);
  await weth.waitForDeployment();
  const dai: MockERC20 = await MockERC20Factory.deploy("Dai Stablecoin", "DAI", 18);
  await dai.waitForDeployment();

  const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
  const ethUsdPriceFeed = await MockV3Aggregator.deploy(3000 * 10 ** 8);
  await ethUsdPriceFeed.waitForDeployment();
  const daiUsdPriceFeed = await MockV3Aggregator.deploy(1 * 10 ** 8);
  await daiUsdPriceFeed.waitForDeployment();

  const ChainlinkOracleAdapter = await ethers.getContractFactory("ChainlinkOracleAdapter");
  const oracle = await ChainlinkOracleAdapter.deploy(deployer.address);
  await oracle.waitForDeployment();

  const DefaultInterestRateModel = await ethers.getContractFactory("DefaultInterestRateModel");
  const interestRateModel = await DefaultInterestRateModel.deploy();
  await interestRateModel.waitForDeployment();

  const LendingPoolFactory = await ethers.getContractFactory("LendingPool");
  const lendingPool: LendingPool = await LendingPoolFactory.deploy(await oracle.getAddress());
  await lendingPool.waitForDeployment();

  const ATokenFactory = await ethers.getContractFactory("aToken");
  const aWeth: aToken = await ATokenFactory.deploy(await weth.getAddress(), await lendingPool.getAddress(), "MiniAave WETH", "aWETH");
  await aWeth.waitForDeployment();
  const aDai: aToken = await ATokenFactory.deploy(await dai.getAddress(), await lendingPool.getAddress(), "MiniAave DAI", "aDAI");
  await aDai.waitForDeployment();

  // --- 2. Configure Contracts ---
  console.log("\n--- Configuring Contracts ---");
  await oracle.setAssetFeed(await weth.getAddress(), await ethUsdPriceFeed.getAddress());
  await oracle.setAssetFeed(await dai.getAddress(), await daiUsdPriceFeed.getAddress());
  await lendingPool.initReserve(await weth.getAddress(), await aWeth.getAddress(), await interestRateModel.getAddress());
  await lendingPool.initReserve(await dai.getAddress(), await aDai.getAddress(), await interestRateModel.getAddress());

  console.log("\n--- Starting Interactions ---");

  // --- 3. Mint Mock Tokens ---
  const wethAmount = ethers.parseEther("10");
  const daiAmount = ethers.parseEther("10000");
  await weth.mint(deployer.address, wethAmount);
  await dai.mint(deployer.address, daiAmount);
  console.log(`Minted ${ethers.formatEther(wethAmount)} WETH and ${ethers.formatEther(daiAmount)} DAI to deployer`);

  // --- 4. Approve LendingPool to spend tokens ---
  await weth.approve(await lendingPool.getAddress(), ethers.MaxUint256);
  await dai.approve(await lendingPool.getAddress(), ethers.MaxUint256);
  console.log("Approved LendingPool to spend WETH and DAI");

  // --- 5. Deposit WETH ---
  const depositAmountWETH = ethers.parseEther("5");
  await lendingPool.deposit(await weth.getAddress(), depositAmountWETH);
  console.log(`Deposited ${ethers.formatEther(depositAmountWETH)} WETH`);
  let aWethBalance = await aWeth.balanceOf(deployer.address);
  console.log(`aWETH balance: ${ethers.formatEther(aWethBalance)}`);

  // --- 6. Enable WETH as Collateral ---
  await lendingPool.setUserUseAsCollateral(await weth.getAddress(), true);
  console.log("Enabled WETH as collateral");

  // --- 7. Borrow DAI ---
  const borrowAmountDAI = ethers.parseEther("1000");
  await lendingPool.borrow(await dai.getAddress(), borrowAmountDAI);
  console.log(`Borrowed ${ethers.formatEther(borrowAmountDAI)} DAI`);
  let daiBalance = await dai.balanceOf(deployer.address);
  console.log(`DAI balance: ${ethers.formatEther(daiBalance)}`);

  // --- 8. Repay DAI ---
  const repayAmountDAI = ethers.parseEther("500");
  await lendingPool.repay(await dai.getAddress(), repayAmountDAI);
  console.log(`Repaid ${ethers.formatEther(repayAmountDAI)} DAI`);
  daiBalance = await dai.balanceOf(deployer.address);
  console.log(`DAI balance: ${ethers.formatEther(daiBalance)}`);

  // --- 9. Withdraw WETH ---
  const withdrawAmountWETH = ethers.parseEther("2");
  await lendingPool.withdraw(await weth.getAddress(), withdrawAmountWETH);
  console.log(`Withdrew ${ethers.formatEther(withdrawAmountWETH)} WETH`);
  aWethBalance = await aWeth.balanceOf(deployer.address);
  console.log(`aWETH balance: ${ethers.formatEther(aWethBalance)}`);

  console.log("\n--- Interaction Example Complete! ---");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
