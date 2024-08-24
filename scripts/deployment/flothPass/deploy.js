// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");

async function main() {
  try {
    // Deploying
    console.log("Getting FlothPass contract...");
    const FlothPass = await ethers.getContractFactory("FlothPass");

    console.log("Deploying FlothPass...");
    const flothPass = await upgrades.deployProxy(FlothPass, ["0xB14BE17241574b1ee506EAA6952D98d45f9E6532"], { initializer: "initialize" });

    await flothPass.waitForDeployment();

    const flothPassAddress = await flothPass.getAddress();

    console.log("FlothPass deployed to:", flothPassAddress);
  } catch (error) {
    console.error("An error occurred :" + error);
  }

  // Upgrading
  // const BoxV2 = await ethers.getContractFactory("BoxV2");
  // const upgraded = await upgrades.upgradeProxy(
  //   await instance.getAddress(),
  //   BoxV2
  // );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
