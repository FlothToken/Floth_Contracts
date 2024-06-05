// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const flothAddress = "0xd6a024303Ad266a34Aab8ca74F40d4E361ACb797"; // Replace with the correct address

  const ProjectProposal = await ethers.getContractFactory("ProjectProposal");
  const projectProposal = await ProjectProposal.deploy(flothAddress);

  await projectProposal.waitForDeployment();

  // Get the address of the deployed contract
  const projectProposalAddress = await projectProposal.getAddress();

  console.log("ProjectProposal deployed to:", projectProposalAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
