// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const floth = await ethers.getContractFactory("Floth");

  const flothContract = await floth.deploy(["0x315c76C23e8815Fe0dFd8DD626782C49647924Ba"], "FLOTH", "FLOTH");

  await flothContract.waitForDeployment();

  // Get the address of the deployed contract
  const flothAddress = await flothContract.getAddress();

  console.log("floth deployed to:", flothAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
