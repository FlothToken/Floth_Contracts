const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("FlothPass Contract", function () {
  let Floth, floth, FlothPass, flothPass, owner, addr1, addr2, dexAddress;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const WITHDRAW_ROLE = ethers.keccak256(ethers.toUtf8Bytes("WITHDRAW_ROLE"));

  const zeroAddress = "0x0000000000000000000000000000000000000000";

  const flothContractAddress = "0xa2EA5Cb0614f6428421a39ec09B013cC3336EFBe";

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
    it("Should set the correct roles", async function () {
      expect(await flothPass.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
      expect(await flothPass.hasRole(ADMIN_ROLE, addr1.address)).to.be.false;
    });

    it("Should initialize the max supply correctly", async function () {
      expect(await flothPass.maxSupply()).to.equal(333);
    });

    it("Should initialize the flothContract correctly", async function () {
      expect(await flothPass.flothContract()).to.equal(flothContractAddress);
    });

    it("Should initialize the flothVault correctly", async function () {
      expect(await flothPass.flothVault()).to.equal("0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739");
    });

    it("Should initialize the withdrawAddress correctly", async function () {
      expect(await flothPass.withdrawAddress()).to.equal("0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739");
    });

    it("Should initialize the _currentBaseURI correctly", async function () {
      expect(await flothPass._currentBaseURI()).to.equal("");
    });

    it("Should initialize the price correctly", async function () {
      expect(await flothPass.price()).to.equal(ethers.parseUnits("1000", 18));
    });

    it("Should initialize the priceIncrement correctly", async function () {
      expect(await flothPass.priceIncrement()).to.equal(ethers.parseUnits("50", 18));
    });
  });

  describe("Setters", function () {
    it("Should allow admins to set the flothContract address", async function () {
      const newFlothAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await flothPass.connect(owner).setFlothContract(newFlothAddress);

      expect(await flothPass.flothContract()).to.equal(newFlothAddress);
    });

    it("Should allow admins to set the setBaseUri", async function () {
      await flothPass.connect(owner).setBaseUri("https://api.flothpass.com/");

      expect(await flothPass._currentBaseURI()).to.equal("https://api.flothpass.com/");
    });

    it("Should not allow non-admins to set the flothContract address", async function () {
      const newFlothAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await expect(flothPass.connect(addr1).setFlothContract(newFlothAddress)).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );

      expect(await flothPass.flothContract()).to.equal(flothContractAddress);
    });

    it("Should revert if the floth contract is set to a zero address", async function () {
      await expect(flothPass.connect(owner).setFlothContract(zeroAddress)).to.be.revertedWithCustomError(flothPass, "CannotDeployAsZeroAddress");
    });
  });
});
