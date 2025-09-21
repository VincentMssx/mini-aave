import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // --- 1. Deploy Mock ERC20 Tokens ---
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  // Deploy WETH with 18 decimals
  const weth = await MockERC20.deploy("Wrapped Ether", "WETH", 18);
  await weth.waitForDeployment();
  console.log("MockWETH deployed to:", await weth.getAddress());

  // Deploy DAI with 18 decimals
  const dai = await MockERC20.deploy("Dai Stablecoin", "DAI", 18);
  await dai.waitForDeployment();
  console.log("MockDAI deployed to:", await dai.getAddress());

  // --- 2. Deploy Mock Price Feeds ---
  const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
  // ETH/USD price feed (e.g., $3000)
  const ethUsdPriceFeed = await MockV3Aggregator.deploy(3000 * 10 ** 8); // Chainlink has 8 decimals for ETH/USD
  await ethUsdPriceFeed.waitForDeployment();
  console.log("ETH/USD Price Feed deployed to:", await ethUsdPriceFeed.getAddress());
  
  // DAI/USD price feed (e.g., $1)
  const daiUsdPriceFeed = await MockV3Aggregator.deploy(1 * 10 ** 8); // $1
  await daiUsdPriceFeed.waitForDeployment();
  console.log("DAI/USD Price Feed deployed to:", await daiUsdPriceFeed.getAddress());

  // --- 3. Deploy Core Contracts ---
  const ChainlinkOracleAdapter = await ethers.getContractFactory("ChainlinkOracleAdapter");
  const oracle = await ChainlinkOracleAdapter.deploy(deployer.address);
  await oracle.waitForDeployment();
  console.log("ChainlinkOracleAdapter deployed to:", await oracle.getAddress());
  
  const DefaultInterestRateModel = await ethers.getContractFactory("DefaultInterestRateModel");
  const interestRateModel = await DefaultInterestRateModel.deploy();
  await interestRateModel.waitForDeployment();
  console.log("DefaultInterestRateModel deployed to:", await interestRateModel.getAddress());
  
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.deploy(await oracle.getAddress());
  await lendingPool.waitForDeployment();
  console.log("LendingPool deployed to:", await lendingPool.getAddress());

  // --- 4. Deploy aTokens ---
  const AToken = await ethers.getContractFactory("aToken");
  // aWETH
  const aWeth = await AToken.deploy(await weth.getAddress(), await lendingPool.getAddress(), "MiniAave WETH", "aWETH");
  await aWeth.waitForDeployment();
  console.log("aWETH deployed to:", await aWeth.getAddress());

  // aDAI
  const aDai = await AToken.deploy(await dai.getAddress(), await lendingPool.getAddress(), "MiniAave DAI", "aDAI");
  await aDai.waitForDeployment();
  console.log("aDAI deployed to:", await aDai.getAddress());

  // --- 5. Configure Contracts (Initialize Reserves & Set Oracles) ---
  console.log("\nConfiguring contracts...");

  // Set price feeds in the oracle adapter
  await oracle.setAssetFeed(await weth.getAddress(), await ethUsdPriceFeed.getAddress());
  console.log(`Set WETH price feed in Oracle`);
  await oracle.setAssetFeed(await dai.getAddress(), await daiUsdPriceFeed.getAddress());
  console.log(`Set DAI price feed in Oracle`);

  // Initialize reserves in the LendingPool
  await lendingPool.initReserve(await weth.getAddress(), await aWeth.getAddress(), await interestRateModel.getAddress());
  console.log(`Initialized WETH reserve`);
  await lendingPool.initReserve(await dai.getAddress(), await aDai.getAddress(), await interestRateModel.getAddress());
  console.log(`Initialized DAI reserve`);
  
  console.log("\nDeployment and configuration complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});