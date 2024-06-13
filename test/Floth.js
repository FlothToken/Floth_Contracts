const { expect } = require("chai");
const { ethers } = require("hardhat");

const zeroBytes32 = "0x0000000000000000000000000000000000000000000000000000000000000000";
const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("Floth Contract", function () {
  let Floth;
  let floth;
  let owner;
  let addr1;
  let addr2;
  let dexAddress;
  let addrs;

  beforeEach(async function () {
    Floth = await ethers.getContractFactory("Floth");
    [owner, addr1, addr2, dexAddress, ...addrs] = await ethers.getSigners();

    floth = await Floth.deploy([dexAddress.address], "Floth Token", "FLOTH");
    await floth.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await floth.owner()).to.equal(owner.address);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await floth.balanceOf(owner.address);
      expect(await floth.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      await floth.transfer(addr1.address, 50);
      const addr1Balance = await floth.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(50);

      await floth.connect(addr1).transfer(addr2.address, 50);
      const addr2Balance = await floth.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(50);
    });

    it("Should fail if sender doesn’t have enough tokens", async function () {
      const initialOwnerBalance = await floth.balanceOf(owner.address);
      await expect(floth.connect(addr1).transfer(owner.address, 1)).to.be.revertedWith("ERC20: transfer amount exceeds balance");

      expect(await floth.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it("Should apply buy tax when buying from a dex address", async function () {
      await floth.transfer(dexAddress.address, 100);
      await floth.connect(dexAddress).transfer(addr1.address, 100);

      const addr1Balance = await floth.balanceOf(addr1.address);
      const grantFundBalance = await floth.balanceOf(floth.grantFundWallet());

      expect(addr1Balance).to.equal(75); // 25% tax applied
      expect(grantFundBalance).to.equal(25);
    });

    it("Should apply sell tax when selling to a dex address", async function () {
      await floth.transfer(addr1.address, 100);
      await floth.connect(addr1).transfer(dexAddress.address, 100);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundBalance = await floth.balanceOf(floth.grantFundWallet());
      const lpPairBalance = await floth.balanceOf(floth.lpPairAddress());

      console.log(dexBalance, grantFundBalance, lpPairBalance);

      expect(dexBalance).to.equal(65); // 35% tax applied
      expect(grantFundBalance).to.equal(29); // 83.3% of 35%
      expect(lpPairBalance).to.equal(6); // 16.7% of 35%
    });
  });

  describe("Admin functions", function () {
    it("Should allow owner to set new buy tax", async function () {
      await floth.setBuyBotTax(400);
      expect(await floth.buyTax()).to.equal(400);
    });

    it("Should revert when non-owner tries to set buy tax", async function () {
      await expect(floth.connect(addr1).setBuyBotTax(400)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow owner to set new sell tax", async function () {
      await floth.setSellBotTax(400);
      expect(await floth.sellTax()).to.equal(400);
    });

    it("Should revert when non-owner tries to set sell tax", async function () {
      await expect(floth.connect(addr1).setSellBotTax(400)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow owner to add and remove dex addresses", async function () {
      await floth.addDexAddress(addr1.address);
      expect(await floth.dexAddresses(addr1.address)).to.equal(true);

      await floth.removeDexAddress(addr1.address);
      expect(await floth.dexAddresses(addr1.address)).to.equal(false);
    });

    it("Should allow owner to set grant fund wallet", async function () {
      await floth.setGrantFundWallet(addr1.address);
      expect(await floth.grantFundWallet()).to.equal(addr1.address);
    });

    it("Should revert when setting grant fund wallet to zero address", async function () {
      await expect(floth.setGrantFundWallet(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should allow owner to set lp pair address", async function () {
      await floth.setLpPairAddress(addr1.address);
      expect(await floth.lpPairAddress()).to.equal(addr1.address);
    });

    it("Should revert when setting lp pair address to zero address", async function () {
      await expect(floth.setLpPairAddress(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });
  });
});
