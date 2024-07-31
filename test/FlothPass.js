const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("FlothPass Contract", function () {
  let Floth, floth, FlothPass, flothPass, owner, addr1, addr2, dexAddress;

  beforeEach(async function () {
    // Get contract factories and signers
    Floth = await ethers.getContractFactory("Floth");
    [owner, addr1, addr2, dexAddress, ...addrs] = await ethers.getSigners();

    // Deploy Floth contract
    floth = await Floth.deploy([dexAddress.address], "Floth Token", "FLOTH");
    await floth.waitForDeployment();

    // Deploy FlothPass contract using deployProxy
    FlothPass = await ethers.getContractFactory("FlothPass");
    flothPass = await upgrades.deployProxy(FlothPass, [], { kind: "transparent" });
    await flothPass.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the max supply correctly", async function () {
      expect(await flothPass.maxSupply()).to.equal(333);
    });
  });
});
