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

  const pFloth = await ethers.getContractFactory("pFloth");
  const pFlothContract = await ProjectProposal.deploy(pFloth);

  await pFlothContract.waitForDeployment();

  // Get the address of the deployed contract
  const pFlothAddress = await pFlothContract.getAddress();

  console.log("pFloth deployed to:", pFlothAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
