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

  describe("Minting", function () {
    it("Should allow a user to mint an NFT", async function () {
      // Activate the sale
      await flothPass.setSaleActive(true);

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      await flothPass.connect(addr1).mint(1);

      expect(await flothPass.getNumberMinted()).to.equal(1);
    });

    it("Should update the vault funds when minting", async function () {
      await flothPass.setSaleActive(true);

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      const balanceBefore = await floth.balanceOf(flothPass.flothVault());

      await flothPass.connect(addr1).mint(1);
      expect(await floth.balanceOf(flothPass.flothVault())).to.equal(ethers.parseUnits("1000", 18));
    });

    it("Should revert if the sale is inactive whilst minting.", async function () {
      //Did not call setSaleActive(true) before minting.

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      await expect(flothPass.connect(addr1).mint(1)).to.be.revertedWithCustomError(flothPass, "SaleInactive");
    });

    it("Should revert if the totalMinted + quantity exceeds the max supply", async function () {
      //setSaleActive(true)
      await flothPass.setSaleActive(true);

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      //Mint 334 NFTs.
      await flothPass.connect(addr1).mint(1);
      await expect(flothPass.connect(addr1).mint(333)).to.be.revertedWithCustomError(flothPass, "ExceedsMaxSupply");
    });

    it("Should update the price after every 10 NFTs sold", async function () {
      //setSaleActive(true)
      await flothPass.setSaleActive(true);

      //Initial price to equal 1000
      expect(await flothPass.price()).to.equal(ethers.parseUnits("1000", 18));

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("10000000000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("10000000000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("10000000000", 18));

      //Mint 9 NFT
      await flothPass.connect(addr1).mint(9);

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("9999991000", 18));

      //expect price to still equal 1000
      expect(await flothPass.price()).to.equal(ethers.parseUnits("1000", 18));

      //Mint 10th NFT
      await flothPass.connect(addr1).mint(1);

      //expect price to still equal 1050
      expect(await flothPass.price()).to.equal(ethers.parseUnits("1050", 18));

      //Check balance decreased by 1000
      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("9999990000", 18));

      //Mint 11th NFT
      await flothPass.connect(addr1).mint(1);

      //Check balance decreased by 1050
      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("9999988950", 18));
    });

    it("Should revert if user tries to mint without enough funds", async function () {
      //setSaleActive(true)
      await flothPass.setSaleActive(true);

      // Transfer some Floth tokens to addr1
      await floth.transfer(addr1.address, ethers.parseUnits("1000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("1000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      //Mint 334 NFTs.
      await flothPass.connect(addr1).mint(1);

      expect(await floth.balanceOf(addr1.address)).to.equal(0);
      await expect(flothPass.connect(addr1).mint(1)).to.be.revertedWithCustomError(flothPass, "InsufficientFunds");
    });
  });

  describe("Withdrawing", function () {
    it("Should allow withdrawal of funds from the FLOTH contract to the withdrawl address", async function () {
      const flothPassAddress = await flothPass.getAddress();

      // Transfer some Floth tokens to floth contract
      await floth.transfer(flothPassAddress, ethers.parseUnits("1000", 18));

      const balanceBefore = await floth.balanceOf(flothPassAddress);
      expect(balanceBefore).to.equal(ethers.parseUnits("1000", 18));

      await flothPass.connect(owner).withdrawFLOTH(0, true);

      const balanceAfter = await floth.balanceOf(flothPassAddress);
      expect(balanceAfter).to.equal(0);

      //Check withdrawAddress balance
      expect(await floth.balanceOf(flothPass.withdrawAddress())).to.equal(ethers.parseUnits("1000", 18));
    });

    it("Should revert when withdrawing FLOTH if insufficient role", async function () {
      const flothPassAddress = await flothPass.getAddress();

      // Transfer some Floth tokens to floth contract
      await floth.transfer(flothPassAddress, ethers.parseUnits("1000", 18));

      //Try withdraw with addr1
      await expect(flothPass.connect(addr1).withdrawFLOTH(0, true)).to.be.revertedWithCustomError(flothPass, "InsufficientRole");
    });

    it("Should revert if insufficient funds in contract when withdrawing FLOTH", async function () {
      const flothPassAddress = await flothPass.getAddress();

      // Transfer some Floth tokens to floth contract
      await floth.transfer(flothPassAddress, ethers.parseUnits("1000", 18));

      //Try withdraw with addr1
      await expect(flothPass.connect(owner).withdrawFLOTH(ethers.parseUnits("10000", 18), false)).to.be.revertedWithCustomError(
        flothPass,
        "InsufficientFundsInContract"
      );
    });
  });

  describe("Setters and getters", function () {
    it("Should be able to get the number of minted passes for an address", async function () {
      // Initially, the number of minted passes should be 0
      expect(await flothPass.balanceOf(addr1.address)).to.equal(0);

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
      expect(await flothPass.balanceOf(addr1.address)).to.equal(1);
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
      await expect(flothPass.connect(owner).setFlothContract(zeroAddress)).to.be.revertedWithCustomError(flothPass, "ZeroAddress");
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
