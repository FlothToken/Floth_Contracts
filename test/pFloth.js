const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("pFLOTH Contract", function () {
  let pFLOTH;
  let pFLOTHMock;
  let owner;
  let addr1;
  let addr2;
  let ERC20Mock;
  let startTime;
  let endTime;
  const EXCHANGE_RATE = 10000n;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // Get current block timestamp
    const latestBlock = await ethers.provider.getBlock('latest');
    startTime = BigInt(latestBlock.timestamp) + 3600n; // Start in 1 hour
    endTime = startTime + 3600n; // End in 2 hours

    // Deploy main contract
    const pFLOTHFactory = await ethers.getContractFactory("pFloth");
    pFLOTH = await pFLOTHFactory.deploy(startTime, endTime);
    await pFLOTH.waitForDeployment();

    // Deploy mock contract
    const pFLOTHMockFactory = await ethers.getContractFactory("pFLOTHMock");
    pFLOTHMock = await pFLOTHMockFactory.deploy(startTime, endTime);
    await pFLOTHMock.waitForDeployment();

    // Deploy mock ERC20 for testing token recovery
    const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
    ERC20Mock = await ERC20MockFactory.deploy("Mock Token", "MTK");
    await ERC20Mock.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct presale timing", async function () {
      const presaleInfo = await pFLOTH.presaleInfo();
      expect(presaleInfo.startTime).to.equal(startTime);
      expect(presaleInfo.endTime).to.equal(endTime);
    });

    it("Should not allow invalid presale times", async function () {
      const pFLOTHFactory = await ethers.getContractFactory("pFloth");
      await expect(pFLOTHFactory.deploy(endTime, startTime))
        .to.be.revertedWithCustomError(pFLOTH, "InvalidPresaleTime");
    });
  });

  describe("Presale", function () {
    beforeEach(async function () {
      // Move time to start of presale
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime)]);
      await ethers.provider.send("evm_mine", []);
    });

    it("Should mint the correct amount of pFLOTH tokens", async function () {
      const amountFLR = ethers.parseUnits("1", 18);
      const amountpFLOTH = amountFLR * EXCHANGE_RATE;

      await pFLOTH.connect(addr1).presale({ value: amountFLR });

      expect(await pFLOTH.balanceOf(addr1.address)).to.equal(amountpFLOTH);
      expect(await pFLOTH.totalSupply()).to.equal(amountpFLOTH);
    });

    it("Should revert if presale has not started", async function () {
      // Deploy new contract with future start time
      const latestBlock = await ethers.provider.getBlock('latest');
      const newStartTime = BigInt(latestBlock.timestamp) + 3600n;
      const newEndTime = newStartTime + 3600n;
      const pFLOTHFactory = await ethers.getContractFactory("pFloth");
      const newPFLOTH = await pFLOTHFactory.deploy(newStartTime, newEndTime);

      await expect(newPFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) }))
        .to.be.revertedWithCustomError(pFLOTH, "PresaleNotStarted");
    });

    it("Should revert if presale has ended", async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(endTime) + 1]);
      await ethers.provider.send("evm_mine", []);

      await expect(pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) }))
        .to.be.revertedWithCustomError(pFLOTH, "PresaleEnded");
    });

    it("Should revert if minting exceeds MAX_SUPPLY", async function () {
      const newSupply = BigInt(1000) * BigInt(10 ** 18);
      await pFLOTHMock.setTotalSupply(newSupply);

      const amountFLR = newSupply / EXCHANGE_RATE + BigInt(1);

      await expect(pFLOTHMock.connect(addr1).presale({ value: amountFLR }))
        .to.be.revertedWithCustomError(pFLOTHMock, "ExceedsSupply");
    });

    it("Should revert if minting exceeds WALLET_LIMIT", async function () {
      const newWalletLimit = BigInt(1000) * BigInt(10 ** 18);
      await pFLOTHMock.setWalletLimit(newWalletLimit);

      const amountFLR = newWalletLimit / EXCHANGE_RATE + BigInt(1);

      await expect(pFLOTHMock.connect(addr1).presale({ value: amountFLR }))
        .to.be.revertedWithCustomError(pFLOTHMock, "ExceedsWalletLimit");
    });

    it("Should handle presale pause functionality", async function () {
      await pFLOTH.connect(owner).togglePresalePause();

      await expect(pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) }))
        .to.be.revertedWithCustomError(pFLOTH, "PresaleIsPaused");

      await pFLOTH.connect(owner).togglePresalePause();
      await expect(pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) }))
        .to.not.be.reverted;
    });

    it("Should handle multiple consecutive presale purchases", async function () {
      const amountFLR1 = ethers.parseUnits("1", 18);
      const amountFLR2 = ethers.parseUnits("2", 18);
      
      await pFLOTH.connect(addr1).presale({ value: amountFLR1 });
      await pFLOTH.connect(addr1).presale({ value: amountFLR2 });
      
      const totalExpected = (amountFLR1 + amountFLR2) * EXCHANGE_RATE;
      expect(await pFLOTH.balanceOf(addr1.address)).to.equal(totalExpected);
    });

    it("Should handle combined scenarios", async function () {
      // 1. Make a presale purchase
      const amountFLR = ethers.parseUnits("1", 18);
      const amountpFLOTH = amountFLR * EXCHANGE_RATE;
      await pFLOTH.connect(addr1).presale({ value: amountFLR });
      
      // 2. Try unauthorized transfer
      await expect(pFLOTH.connect(addr1).transfer(addr2.address, amountpFLOTH))
        .to.be.revertedWithCustomError(pFLOTH, "UnauthorizedTransfer");
      
      // 3. Authorize transfer and try again
      await pFLOTH.connect(owner).setAuthorizedReceiver(addr2.address, true);
      await pFLOTH.connect(addr1).transfer(addr2.address, amountpFLOTH);
      
      // 4. Try to recover tokens (should fail for pFLOTH tokens)
      await expect(pFLOTH.connect(owner).recoverTokens(await pFLOTH.getAddress(), amountpFLOTH))
        .to.be.revertedWithCustomError(pFLOTH, "InvalidRecoveryToken");
      
      // 5. Verify final balances
      expect(await pFLOTH.balanceOf(addr2.address)).to.equal(amountpFLOTH);
    });
  });

  describe("Presale Time Management", function () {
    it("Should allow extending presale time", async function () {
      const extension = 3600; // 1 hour
      const oldEndTime = await (await pFLOTH.presaleInfo()).endTime;
      
      await pFLOTH.setPresaleEndTime(oldEndTime + BigInt(extension));
      
      const newEndTime = await (await pFLOTH.presaleInfo()).endTime;
      expect(newEndTime).to.equal(oldEndTime + BigInt(extension));
    });

    it("Should not allow setting end time in the past", async function () {
      const latestBlock = await ethers.provider.getBlock('latest');
      const currentTime = BigInt(latestBlock.timestamp);
      await expect(pFLOTH.setPresaleEndTime(currentTime - 1n))
        .to.be.revertedWithCustomError(pFLOTH, "InvalidPresaleTime");
    });
  });

  describe("Token Transfers", function () {
    it("Should handle authorized receiver transfers", async function () {
      // Set up presale
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime)]);
      await ethers.provider.send("evm_mine", []);
      
      const amountFLR = ethers.parseUnits("1", 18);
      await pFLOTH.connect(addr1).presale({ value: amountFLR });

      // Try transfer before authorization
      await expect(pFLOTH.connect(addr1).transfer(addr2.address, amountFLR))
        .to.be.revertedWithCustomError(pFLOTH, "UnauthorizedTransfer");

      // Authorize receiver and try again
      await pFLOTH.connect(owner).setAuthorizedReceiver(addr2.address, true);
      await expect(pFLOTH.connect(addr1).transfer(addr2.address, amountFLR))
        .to.not.be.reverted;
    });
  });

  describe("Token Recovery", function () {
    beforeEach(async function () {
      // Deploy mock ERC20 and transfer some tokens to the contract
      const amount = ethers.parseUnits("100", 18);
      await ERC20Mock.transfer(await pFLOTH.getAddress(), amount);
    });

    it("Should allow owner to recover tokens", async function () {
      const amount = ethers.parseUnits("50", 18);
      const initialBalance = await ERC20Mock.balanceOf(owner.address);
      
      await expect(pFLOTH.connect(owner).recoverTokens(ERC20Mock.getAddress(), amount))
        .to.not.be.reverted;
      
      const finalBalance = await ERC20Mock.balanceOf(owner.address);
      expect(finalBalance - initialBalance).to.equal(amount);
    });

    it("Should not allow recovering pFLOTH tokens", async function () {
      await expect(pFLOTH.connect(owner).recoverTokens(await pFLOTH.getAddress(), 100))
        .to.be.revertedWithCustomError(pFLOTH, "InvalidRecoveryToken");
    });
  });

  describe("Withdrawal", function () {
    beforeEach(async function () {
      // Set up presale and receive some FLR
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime)]);
      await ethers.provider.send("evm_mine", []);
      
      await pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) });
    });

    it("Should allow owner to withdraw all FLR", async function () {
      const initialBalance = await ethers.provider.getBalance(owner.address);
      await pFLOTH.connect(owner).withdraw();
      const finalBalance = await ethers.provider.getBalance(owner.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
      expect(await ethers.provider.getBalance(pFLOTH.getAddress())).to.equal(0);
    });

    it("Should allow partial withdrawals to specified address", async function () {
      const withdrawAmount = ethers.parseUnits("0.5", 18);
      const initialBalance = await ethers.provider.getBalance(addr2.address);
      
      await pFLOTH.connect(owner).withdrawTo(withdrawAmount, addr2.address);
      
      const finalBalance = await ethers.provider.getBalance(addr2.address);
      expect(finalBalance - initialBalance).to.equal(withdrawAmount);
    });
  });

  describe("Stats and Information", function () {
    it("Should return correct presale stats", async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime)]);
      await ethers.provider.send("evm_mine", []);

      const amountFLR = ethers.parseUnits("1", 18);
      await pFLOTH.connect(addr1).presale({ value: amountFLR });

      const stats = await pFLOTH.getPresaleStats();
      expect(stats.totalRaised).to.equal(amountFLR);
      expect(stats.totalMinted).to.equal(amountFLR * EXCHANGE_RATE);
      expect(stats.isActive).to.be.true;
    });

    it("Should track remaining supply correctly", async function () {
      const initialSupply = await pFLOTH.remainingSupply();
      
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime)]);
      await ethers.provider.send("evm_mine", []);

      const amountFLR = ethers.parseUnits("1", 18);
      await pFLOTH.connect(addr1).presale({ value: amountFLR });

      const finalSupply = await pFLOTH.remainingSupply();
      expect(initialSupply - finalSupply).to.equal(amountFLR * EXCHANGE_RATE);
    });

    it("Should calculate presale time remaining correctly", async function () {
      // Move time to just before start time
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(startTime) - 1]);
      await ethers.provider.send("evm_mine", []);

      // Before presale starts, should return full duration
      const timeRemaining = await pFLOTH.presaleTimeRemaining();
      expect(Number(timeRemaining)).to.be.closeTo(Number(endTime - startTime), 5);

      // Move to middle of presale
      const midTime = Number(startTime) + 1800; // Move 30 minutes into presale
      await ethers.provider.send("evm_setNextBlockTimestamp", [midTime]);
      await ethers.provider.send("evm_mine", []);

      // Should have about half the time remaining
      const midTimeRemaining = await pFLOTH.presaleTimeRemaining();
      expect(Number(midTimeRemaining)).to.be.closeTo(1800, 5); // ~1800 seconds (30 minutes) remaining

      // After presale ends
      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(endTime) + 1]);
      await ethers.provider.send("evm_mine", []);

      // Should return 0 after presale ends
      expect(await pFLOTH.presaleTimeRemaining()).to.equal(0n);
    });
  });
});
