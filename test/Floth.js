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
  let initialGrantFundWallet;
  let initialLpFundWallet;
  let dexAddress;
  let addrs;

  beforeEach(async function () {
    Floth = await ethers.getContractFactory("Floth");
    [owner, addr1, addr2, initialGrantFundWallet, initialLpFundWallet, dexAddress, ...addrs] = await ethers.getSigners();

    floth = await Floth.deploy([dexAddress.address], "Floth Token", "FLOTH");
    await floth.waitForDeployment();

    await floth.setGrantFundWallet(initialGrantFundWallet.address);
    await floth.setLpFundWallet(initialLpFundWallet.address);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await floth.owner()).to.equal(owner.address);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await floth.balanceOf(owner.address);
      expect(await floth.totalSupply()).to.equal(ownerBalance);
    });

    it("Should revert when deploying with empty name or symbol", async function () {
      await expect(Floth.deploy([dexAddress.address], "", "FLOTH")).to.be.revertedWithCustomError(Floth, "InvalidTokenNameOrSymbol");
      await expect(Floth.deploy([dexAddress.address], "Floth Token", "")).to.be.revertedWithCustomError(Floth, "InvalidTokenNameOrSymbol");
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
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);

      // Transfer to DEX without tax
      await floth.transfer(dexAddress.address, 200);

      // Test buy transaction
      await floth.connect(dexAddress).transfer(addr1.address, 100);

      const addr1Balance = await floth.balanceOf(addr1.address);
      const grantFundWallet = await floth.balanceOf(await floth.grantFundWallet());

      expect(addr1Balance).to.equal(75); // 100 - 25% buy tax
      expect(grantFundWallet).to.equal(25); // 25% buy tax
    });

    it("Should apply sell tax when selling to a dex address", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
      await floth.transfer(addr1.address, 1000);
      await floth.connect(addr1).transfer(dexAddress.address, 1000);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundWallet = await floth.balanceOf(await floth.grantFundWallet());
      const lpFundBalance = await floth.balanceOf(await floth.lpFundWallet());

      // For 1000 tokens:
      // 35% sell tax = 350 tokens
      // 0.5% LP tax = 5 tokens
      expect(dexBalance).to.equal(645);
      expect(grantFundWallet).to.equal(350);
      expect(lpFundBalance).to.equal(5);
    });

    it("Should apply correct tax after changing buy tax", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
      await floth.setBuyTax(500); // Set buy tax to 5%
      await floth.transfer(dexAddress.address, 200);
      await floth.connect(dexAddress).transfer(addr1.address, 100);

      const addr1Balance = await floth.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(95); // 5% tax applied
    });

    it("Should apply correct tax after changing sell tax", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
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
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
      await floth.setLpTaxStatus(false); // Disable LP tax

      // Transfer 100 tokens between non-dex addresses, no tax applied
      await floth.transfer(addr1.address, 100);

      // Transfer 100 tokens from addr1 to dex address, only sell tax applied
      // Tax amount = 100 * 0.35 = 35
      // LP tax not active, so LP pair balance doesn't change
      await floth.connect(addr1).transfer(dexAddress.address, 100);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundWallet = await floth.balanceOf(floth.grantFundWallet());
      const lpPairBalance = await floth.balanceOf(floth.lpFundWallet());

      expect(dexBalance).to.equal(65); // 35% tax applied
      expect(grantFundWallet).to.equal(35); // 35% tax
      expect(lpPairBalance).to.equal(0); // (no LP tax)
    });

    it("Should allow transfers initiated by approved spender", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
      await floth.approve(addr1.address, 100);
      await floth.connect(addr1).transferFrom(owner.address, addr2.address, 100);

      const addr2Balance = await floth.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(100);
    });

    it("Should not apply tax on transfers between non-dex addresses", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);
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
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.buyTax).to.equal(400);
    });

    it("Should revert when non-owner tries to set buy tax", async function () {
      await expect(floth.connect(addr1).setBuyTax(400)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow owner to set new sell tax", async function () {
      await floth.setSellTax(400);
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.sellTax).to.equal(400);
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

    it("Should revert when adding dex addresses if address is 0 address", async function () {
      await expect(floth.addDexAddress(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should revert when removing dex addresses if address is 0 address", async function () {
      await floth.addDexAddress(addr1.address);
      expect(await floth.dexAddresses(addr1.address)).to.equal(true);

      await expect(floth.removeDexAddress(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should allow owner to set grant fund wallet", async function () {
      await floth.setGrantFundWallet(addr1.address);
      expect(await floth.grantFundWallet()).to.equal(addr1.address);
    });

    it("Should revert when setting grant fund wallet to zero address", async function () {
      await expect(floth.setGrantFundWallet(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should allow owner to set lp pair address", async function () {
      await floth.setLpFundWallet(addr1.address);
      expect(await floth.lpFundWallet()).to.equal(addr1.address);
    });

    it("Should revert when setting lp pair address to zero address", async function () {
      await expect(floth.setLpFundWallet(zeroAddress)).to.be.revertedWithCustomError(Floth, "ZeroAddress");
    });

    it("Should allow owner to toggle LP tax status", async function () {
      await floth.setLpTaxStatus(false);
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.lpTaxActive).to.equal(false);
      await floth.setLpTaxStatus(true);
      const taxInfo2 = await floth.getTaxInfo();
      expect(taxInfo2.lpTaxActive).to.equal(true);
    });

    it("Should emit events on admin actions", async function () {
      await expect(floth.setBuyTax(400)).to.emit(floth, "BuyTaxUpdate").withArgs(400);
      await expect(floth.setSellTax(400)).to.emit(floth, "SellTaxUpdate").withArgs(400);
      await expect(floth.addDexAddress(addr1.address)).to.emit(floth, "DexAddressAdded").withArgs(addr1.address);
      await expect(floth.removeDexAddress(addr1.address)).to.emit(floth, "DexAddressRemoved").withArgs(addr1.address);
      await expect(floth.setGrantFundWallet(addr1.address)).to.emit(floth, "GrantFundWalletUpdated").withArgs(addr1.address);
      await expect(floth.setLpFundWallet(addr1.address)).to.emit(floth, "LpFundWalletUpdated").withArgs(addr1.address);
    });
  });

  describe("Tax Information", function () {
    it("Should return correct tax information", async function () {
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.buyTax).to.equal(2500); // Initial 25%
      expect(taxInfo.sellTax).to.equal(3500); // Initial 35%
      expect(taxInfo.lpTaxActive).to.equal(true);
      expect(taxInfo.paused).to.equal(false);
    });

    it("Should update tax info when values change", async function () {
      await floth.setBuyTax(300); // 3%
      await floth.setSellTax(400); // 4%
      await floth.setLpTaxStatus(false);

      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.buyTax).to.equal(300);
      expect(taxInfo.sellTax).to.equal(400);
      expect(taxInfo.lpTaxActive).to.equal(false);
    });
  });

  describe("Emergency Pause", function () {
    it("Should allow owner to toggle pause", async function () {
      await floth.togglePause();
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.paused).to.equal(true);
    });

    it("Should prevent transfers when paused", async function () {
      await floth.togglePause();
      await expect(floth.transfer(addr1.address, 100)).to.be.revertedWithCustomError(floth, "Paused");
    });

    it("Should allow transfers after unpause", async function () {
      await floth.togglePause();
      await floth.togglePause(); // unpause
      await floth.transfer(addr1.address, 100);
      expect(await floth.balanceOf(addr1.address)).to.equal(100);
    });
  });

  describe("Invalid Operations", function () {
    it("Should revert on zero amount transfers", async function () {
      await expect(floth.transfer(addr1.address, 0)).to.be.revertedWithCustomError(floth, "ZeroAmount");
    });

    it("Should revert on transfers to self", async function () {
      await expect(floth.transfer(owner.address, 100)).to.be.revertedWithCustomError(floth, "SelfTransfer");
    });
  });

  describe("Delegation", function () {
    it("Should auto-delegate to self on first transfer", async function () {
      await floth.transfer(addr1.address, 100);
      expect(await floth.delegates(addr1.address)).to.equal(addr1.address);
    });

    it("Should maintain delegation on subsequent transfers", async function () {
      await floth.transfer(addr1.address, 100);
      await floth.connect(addr1).transfer(addr2.address, 50);
      expect(await floth.delegates(addr1.address)).to.equal(addr1.address);
      expect(await floth.delegates(addr2.address)).to.equal(addr2.address);
    });
  });

  describe("Tax Calculations", function () {
    it("Should calculate taxes correctly on sell transactions", async function () {
      await floth.setLiquidityProvider(owner.address, true);

      console.log("Initial owner balance:", (await floth.balanceOf(owner.address)).toString());

      // First transfer to addr1
      await floth.transfer(addr1.address, 1000);
      console.log("Addr1 balance after transfer:", (await floth.balanceOf(addr1.address)).toString());

      // Then addr1 sells to DEX
      await floth.connect(addr1).transfer(dexAddress.address, 1000);

      const dexBalance = await floth.balanceOf(dexAddress.address);
      const grantFundWallet = await floth.balanceOf(await floth.grantFundWallet());
      const lpFundBalance = await floth.balanceOf(await floth.lpFundWallet());

      console.log("DEX balance:", dexBalance.toString());
      console.log("Grant Fund balance:", grantFundWallet.toString());
      console.log("LP Fund balance:", lpFundBalance.toString());

      expect(dexBalance).to.equal(645);
      expect(grantFundWallet).to.equal(350);
      expect(lpFundBalance).to.equal(5);
    });

    it("Should calculate taxes correctly on buy transactions", async function () {
      // Set up as liquidity provider for initial DEX transfer
      await floth.setLiquidityProvider(owner.address, true);

      // First transfer to DEX
      await floth.transfer(dexAddress.address, 1000);

      // Then DEX sells to addr1 (triggers buy tax)
      await floth.connect(dexAddress).transfer(addr1.address, 1000);

      // Buy tax (25%) of 1000 = 250 tokens
      // addr1 receives = 1000 - 250 = 750 tokens

      const addr1Balance = await floth.balanceOf(addr1.address);
      const grantFundWallet = await floth.balanceOf(await floth.grantFundWallet());

      expect(addr1Balance).to.equal(750);
      expect(grantFundWallet).to.equal(250);
    });
  });

  describe("LP Tax Settings", function () {
    it("Should set LP tax correctly", async function () {
      await floth.setLpTax(50); // 0.5%
      const taxInfo = await floth.getTaxInfo();
      expect(taxInfo.lpTax).to.equal(50);
    });

    it("Should emit event when LP tax status changes", async function () {
      await expect(floth.setLpTaxStatus(false)).to.emit(floth, "LpTaxStatusUpdate").withArgs(false);
    });
  });

  describe("Events", function () {
    it("Should emit correct events for all tax updates", async function () {
      await expect(floth.setBuyTax(300)).to.emit(floth, "BuyTaxUpdate").withArgs(300);

      await expect(floth.setSellTax(400)).to.emit(floth, "SellTaxUpdate").withArgs(400);

      await expect(floth.setLpTax(50)).to.emit(floth, "LpTaxUpdate").withArgs(50);
    });
  });

  describe("Grant Fund", function () {
    it("Should return correct grant fund wallet address", async function () {
      const grantFundWallet = await floth.grantFundWallet();
      expect(grantFundWallet).to.equal(initialGrantFundWallet);
    });

    it("Should calculate grant fund split correctly", async function () {
      await floth.transfer(addr1.address, 1000);
      await floth.connect(addr1).transfer(dexAddress.address, 1000);

      // 35% sell tax of 1000 = 350 tokens
      const grantFundWallet = await floth.balanceOf(await floth.grantFundWallet());
      expect(grantFundWallet).to.equal(350);
    });
  });

  describe("Liquidity Provider", function () {
    it("Should allow owner to set liquidity provider status", async function () {
      await expect(floth.setLiquidityProvider(addr1.address, true)).to.emit(floth, "LiquidityProviderUpdated").withArgs(addr1.address, true);

      expect(await floth.liquidityProviders(addr1.address)).to.equal(true);
    });

    it("Should revert when non-owner tries to set liquidity provider", async function () {
      await expect(floth.connect(addr1).setLiquidityProvider(addr1.address, true)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should revert when setting zero address as liquidity provider", async function () {
      await expect(floth.setLiquidityProvider(zeroAddress, true)).to.be.revertedWithCustomError(floth, "ZeroAddress");
    });

    it("Should allow tax-free transfers to DEX from liquidity provider", async function () {
      // Set up liquidity provider
      await floth.setLiquidityProvider(owner.address, true);

      // Get initial balances
      const initialDexBalance = await floth.balanceOf(dexAddress.address);
      const initialGrantFundBalance = await floth.balanceOf(await floth.grantFundWallet());

      // Transfer to DEX
      const transferAmount = 1000;
      await floth.transfer(dexAddress.address, transferAmount);

      // Check balances
      const finalDexBalance = await floth.balanceOf(dexAddress.address);
      const finalGrantFundBalance = await floth.balanceOf(await floth.grantFundWallet());

      // DEX should receive full amount
      expect(finalDexBalance - initialDexBalance).to.equal(transferAmount);
      // Grant fund should not receive any tax
      expect(finalGrantFundBalance).to.equal(initialGrantFundBalance);
    });

    it("Should apply taxes after liquidity provider status is removed", async function () {
      // Set up and remove liquidity provider
      await floth.setLiquidityProvider(owner.address, true);
      await floth.setLiquidityProvider(owner.address, false);

      // Transfer to DEX
      const transferAmount = 1000;
      await floth.transfer(dexAddress.address, transferAmount);

      // Check that normal sell tax was applied
      const expectedTax = transferAmount * (35 / 100); // 35% sell tax
      const grantFundBalance = await floth.balanceOf(await floth.grantFundWallet());
      expect(grantFundBalance).to.equal(expectedTax);
    });

    it("Should handle multiple liquidity providers correctly", async function () {
      // Set up multiple LPs
      await floth.setLiquidityProvider(addr1.address, true);
      await floth.setLiquidityProvider(addr2.address, true);

      // Transfer tokens to LPs
      const transferAmount = 1000;
      await floth.transfer(addr1.address, transferAmount);
      await floth.transfer(addr2.address, transferAmount);

      // Both LPs should be able to transfer to DEX tax-free
      await floth.connect(addr1).transfer(dexAddress.address, transferAmount);
      await floth.connect(addr2).transfer(dexAddress.address, transferAmount);

      // Grant fund should not receive any tax
      const grantFundBalance = await floth.balanceOf(await floth.grantFundWallet());
      expect(grantFundBalance).to.equal(0);
    });

    it("Should simulate complete LP setup process", async function () {
      // 1. Set up LP
      await floth.setLiquidityProvider(owner.address, true);

      // 2. Transfer initial liquidity
      const lpAmount = 1000;
      await floth.transfer(dexAddress.address, lpAmount);

      // 3. Remove LP status
      await floth.setLiquidityProvider(owner.address, false);

      // 4. Verify normal trading works with taxes
      const tradeAmount = 1000;
      await floth.transfer(dexAddress.address, tradeAmount);

      // Check tax was applied to normal trade
      const expectedTax = (tradeAmount * 35) / 100;
      const grantFundBalance = await floth.balanceOf(await floth.grantFundWallet());
      expect(grantFundBalance).to.equal(expectedTax);
    });
  });
});
