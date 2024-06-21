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
      //Owner transfers 100 tokens to dex address
      //200 * 0.35 = sale tax = 70
      //70 * 0.8333 = grant fund balance = 58.33
      //70 - 58.33 = lp pair balance = 11.67
      //dex address balance = 200 - 70 = 130
      await floth.transfer(dexAddress.address, 200);

      //   console.log("Dex Balance: ", await floth.balanceOf(dexAddress.address));
      //   console.log("Grant Fund Balance: ", await floth.balanceOf(floth.grantFundWallet()));
      //   console.log("LP Pair Balance: ", await floth.balanceOf(floth.lpPairAddress()));

      //Dex address transfers 100 tokens to addr1
      //100 * 0.25 = tax = 25
      //addr1 balance = 100 - 25 = 75
      //grant fund balance = 58.33 + 25 = 83.33
      await floth.connect(dexAddress).transfer(addr1.address, 100);

      const addr1Balance = await floth.balanceOf(addr1.address);
      const grantFundBalance = await floth.balanceOf(floth.grantFundWallet());

      //   console.log("Addr1 Balance: ", addr1Balance);
      //   console.log("Dex Balance: ", await floth.balanceOf(dexAddress.address));
      //   console.log("Grant Fund Balance: ", await floth.balanceOf(floth.grantFundWallet()));
      //   console.log("LP Pair Balance: ", await floth.balanceOf(floth.lpPairAddress()));

      expect(addr1Balance).to.equal(75); // 25% tax applied
      expect(grantFundBalance).to.equal(83);
    });

    it("Should apply sell tax when selling to a dex address", async function () {
      //Owner transfers 100 tokens to addr1
      //Neither buy nor sell tax is applied as no dex address is involved

      //Addr1 transfers 100 tokens to dex address
      //This is a sell
      //100 * 0.35 = tax = 35
      //35 * 0.8333 = grant fund balance = 29.17
      //35 - 29.17 = lp pair balance = 5.83
      //dex address balance = 100 - 35 = 65
      await floth.transfer(addr1.address, 100);
      await floth.connect(addr1).transfer(dexAddress.address, 100);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundBalance = await floth.balanceOf(floth.grantFundWallet());
      const lpPairBalance = await floth.balanceOf(floth.lpFundWallet());

      //   console.log(dexBalance, grantFundBalance, lpPairBalance);

      expect(dexBalance).to.equal(65); // 35% tax applied
      expect(grantFundBalance).to.equal(29); // 83.3% of 35%
      expect(lpPairBalance).to.equal(6); // 16.7% of 35%
    });

    it("Should apply correct tax after changing buy tax", async function () {
      await floth.setBuyTax(500); // Set buy tax to 5%
      await floth.transfer(dexAddress.address, 200);
      await floth.connect(dexAddress).transfer(addr1.address, 100);

      const addr1Balance = await floth.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(95); // 5% tax applied
    });

    it("Should apply correct tax after changing sell tax", async function () {
      await floth.setSellTax(500); // Set sell tax to 5%
      await floth.transfer(addr1.address, 200);
      await floth.connect(addr1).transfer(dexAddress.address, 100);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      expect(dexBalance).to.equal(95); // 5% tax applied
    });

    it("Should allow large token transfers", async function () {
      await floth.transfer(addr1.address, 100000);
      const addr1Balance = await floth.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(100000);
    });

    it("Should handle LP tax status change", async function () {
      await floth.setLpTaxStatus(false); // Disable LP tax

      // Transfer 100 tokens between non-dex addresses, no tax applied
      await floth.transfer(addr1.address, 100);

      // Transfer 100 tokens from addr1 to dex address, only sell tax applied
      // Tax amount = 100 * 0.35 = 35
      // Grant fund balance = 35 * 0.8333 = 29.17
      // LP tax not active, so LP pair balance doesn't change
      await floth.connect(addr1).transfer(dexAddress.address, 100);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundBalance = await floth.balanceOf(floth.grantFundWallet());
      const lpPairBalance = await floth.balanceOf(floth.lpFundWallet());

      expect(dexBalance).to.equal(65); // 35% tax applied
      expect(grantFundBalance).to.equal(29); // 83% of 35% tax
      expect(lpPairBalance).to.equal(0); // (no LP tax)
    });

    it("Should allow transfers initiated by approved spender", async function () {
      await floth.approve(addr1.address, 100);
      await floth.connect(addr1).transferFrom(owner.address, addr2.address, 100);

      const addr2Balance = await floth.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(100);
    });

    it("Should not apply tax on transfers between non-dex addresses", async function () {
      await floth.transfer(addr1.address, 100);
      await floth.connect(addr1).transfer(addr2.address, 50);

      const addr2Balance = await floth.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(50); // No tax applied
    });

    it("Should revert when setting buy tax beyond limit", async function () {
      await expect(floth.setBuyTax(600)).to.be.revertedWithCustomError(floth, "InvalidTaxAmount");
    });

    it("Should revert when setting sell tax beyond limit", async function () {
      await expect(floth.setSellTax(600)).to.be.revertedWithCustomError(floth, "InvalidTaxAmount");
    });

    it("Should revert when self transferring", async function () {
      await expect(floth.transfer(owner.address, 50)).to.be.revertedWithCustomError(floth, "SelfTransfer");
    });
  });

  describe("Allowances", function () {
    it("Should revert when transferring more than the allowance", async function () {
      await floth.transfer(addr1.address, 100);
      await floth.approve(addr1.address, 50);
      await expect(floth.connect(addr1).transferFrom(owner.address, addr2.address, 51)).to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("Should decrease the allowance", async function () {
      await floth.approve(addr1.address, 100);
      await floth.connect(owner).decreaseAllowance(addr1.address, 50);
      const allowance = await floth.allowance(owner.address, addr1.address);
      expect(allowance).to.equal(50);
    });

    it("Should increase the allowance", async function () {
      await floth.approve(addr1.address, 50);
      await floth.connect(owner).increaseAllowance(addr1.address, 50);
      const allowance = await floth.allowance(owner.address, addr1.address);
      expect(allowance).to.equal(100);
    });

    it("Should reset the allowance correctly", async function () {
      await floth.approve(addr1.address, 100);
      await floth.connect(owner).approve(addr1.address, 0);
      const allowance = await floth.allowance(owner.address, addr1.address);
      expect(allowance).to.equal(0);
    });

    it("Should emit Approval event", async function () {
      await expect(floth.approve(addr1.address, 100)).to.emit(floth, "Approval").withArgs(owner.address, addr1.address, 100);
    });
  });

  describe("Admin functions", function () {
    it("Should allow owner to set new buy tax", async function () {
      await floth.setBuyTax(400);
      expect(await floth.buyTax()).to.equal(400);
    });

    it("Should revert when non-owner tries to set buy tax", async function () {
      await expect(floth.connect(addr1).setBuyTax(400)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow owner to set new sell tax", async function () {
      await floth.setSellTax(400);
      expect(await floth.sellTax()).to.equal(400);
    });

    it("Should revert when non-owner tries to set sell tax", async function () {
      await expect(floth.connect(addr1).setSellTax(400)).to.be.revertedWith("Ownable: caller is not the owner");
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
      await floth.setLpFundWalletAddress(addr1.address);
      expect(await floth.lpFundWallet()).to.equal(addr1.address);
    });

    it("Should revert when setting lp pair address to zero address", async function () {
      await expect(floth.setLpFundWalletAddress(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should allow owner to toggle LP tax status", async function () {
      await floth.setLpTaxStatus(false);
      expect(await floth.lpTaxIsActive()).to.equal(false);
      await floth.setLpTaxStatus(true);
      expect(await floth.lpTaxIsActive()).to.equal(true);
    });

    it("Should emit events on admin actions", async function () {
      await expect(floth.setBuyTax(400)).to.emit(floth, "BuyTaxUpdate").withArgs(400);
      await expect(floth.setSellTax(400)).to.emit(floth, "SellTaxUpdate").withArgs(400);
      await expect(floth.addDexAddress(addr1.address)).to.emit(floth, "DexAddressAdded").withArgs(addr1.address);
      await expect(floth.removeDexAddress(addr1.address)).to.emit(floth, "DexAddressRemoved").withArgs(addr1.address);
      await expect(floth.setGrantFundWallet(addr1.address)).to.emit(floth, "GrantFundWalletUpdated").withArgs(addr1.address);
      await expect(floth.setLpFundWalletAddress(addr1.address)).to.emit(floth, "LpFundWalletUpdated").withArgs(addr1.address);
    });
  });
});
