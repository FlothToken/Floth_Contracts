const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("FlothPass Contract", function () {
  let Floth, floth, FlothPass, flothPass, owner, addr1, addr2, dexAddress, flothAddress;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const WITHDRAW_ROLE = ethers.keccak256(ethers.toUtf8Bytes("WITHDRAW_ROLE"));

  const zeroAddress = "0x0000000000000000000000000000000000000000";

  beforeEach(async function () {
    // Get contract factories and signers
    Floth = await ethers.getContractFactory("Floth");
    [owner, addr1, addr2, dexAddress, ...addrs] = await ethers.getSigners();

    // Deploy Floth contract
    floth = await Floth.deploy([dexAddress.address], "Floth Token", "FLOTH");
    await floth.waitForDeployment();

    flothAddress = await floth.getAddress();

    // Deploy FlothPass contract using deployProxy
    FlothPass = await ethers.getContractFactory("FlothPass");
    flothPass = await upgrades.deployProxy(FlothPass, [flothAddress], { kind: "transparent" });
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
      expect(await flothPass.flothContract()).to.equal(flothAddress);
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

  describe("Setters and getters", function () {
    it("Should be able to get the number of minted passes for an address", async function () {
      // Initially, the number of minted passes should be 0
      expect(await flothPass.numberMinted(addr1.address)).to.equal(0);

      // Activate the sale
      await flothPass.setSaleActive(true);

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      // Check the balance of addr1
      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      // Mint a pass from addr1
      await flothPass.connect(addr1).mint(1);

      // Check the number of minted passes for addr1
      expect(await flothPass.numberMinted(addr1.address)).to.equal(1);
    });

    it("Should allow admins to set the flothContract address", async function () {
      const newFlothAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await flothPass.connect(owner).setFlothContract(newFlothAddress);

      expect(await flothPass.flothContract()).to.equal(newFlothAddress);
    });

    it("Should not allow non-admins to set the flothContract address", async function () {
      const newFlothAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await expect(flothPass.connect(addr1).setFlothContract(newFlothAddress)).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });

    it("Should revert if the floth contract is set to a zero address", async function () {
      await expect(flothPass.connect(owner).setFlothContract(zeroAddress)).to.be.revertedWithCustomError(flothPass, "CannotDeployAsZeroAddress");
    });

    it("Should allow admins to set the setBaseUri", async function () {
      await flothPass.connect(owner).setBaseUri("https://api.flothpass.com/");

      expect(await flothPass._currentBaseURI()).to.equal("https://api.flothpass.com/");
    });

    it("Should not allow non-admins to set the symbol", async function () {
      await expect(flothPass.connect(addr1).setBaseUri("test")).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });

    it("Should allow admins to set the name", async function () {
      await flothPass.connect(owner).setName("Floth Pass");

      expect(await flothPass.name()).to.equal("Floth Pass");
    });

    it("Should allow admins to set the symbol", async function () {
      await flothPass.connect(owner).setSymbol("0xCrockPASS");

      expect(await flothPass.symbol()).to.equal("0xCrockPASS");
    });

    it("Should not allow non-admins to set the symbol", async function () {
      await expect(flothPass.connect(addr1).setSymbol("0xCrock")).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });

    it("Should allow admins to set the maxSupply", async function () {
      await flothPass.connect(owner).setMaxSupply(666);

      expect(await flothPass.maxSupply()).to.equal(666);
    });

    it("Should allow admins to set the mintPrice", async function () {
      await flothPass.connect(owner).setMintPrice(ethers.parseUnits("500", 18));

      expect(await flothPass.price()).to.equal(ethers.parseUnits("500", 18));
    });

    it("Should not allow non-admins to set the mint price", async function () {
      await expect(flothPass.connect(addr1).setMintPrice(600)).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });

    it("Should allow admins to set the withdrawAddress", async function () {
      const newWithdrawAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";
      await flothPass.connect(owner).setWithdrawAddress(newWithdrawAddress);

      expect(await flothPass.withdrawAddress()).to.equal(newWithdrawAddress);
    });

    it("Should not allow non-admins to set the withdrawAddress", async function () {
      const newWithdrawAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await expect(flothPass.connect(addr1).setWithdrawAddress(newWithdrawAddress)).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });

    it("Should allow admins to set the saleActive", async function () {
      await flothPass.connect(owner).setSaleActive(true);

      expect(await flothPass.saleActive()).to.be.true;
    });

    it("Should not allow non-admins to set the saleActive", async function () {
      await expect(flothPass.connect(addr1).setSaleActive(true)).to.be.revertedWith(
        "AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
      );
    });
  });
});
