const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("pFLOTH Contract", function () {
  let pFLOTH;
  let owner;
  let addr1;
  let addr2;
  const PRESALE_DURATION = 3600; // 1 hour
  const EXCHANGE_RATE = 10000n;
  const MAX_SUPPLY = ethers.parseUnits("30000000000", 18); // 30 billion pFLOTH
  const WALLET_LIMIT = ethers.parseUnits("2500000000", 18); // 2.5 billion pFLOTH

  beforeEach(async function () {
    [owner, addr1, addr2, _] = await ethers.getSigners();

    const pFLOTHFactory = await ethers.getContractFactory("pFLOTH");
    pFLOTH = await pFLOTHFactory.deploy(PRESALE_DURATION);
    await pFLOTH.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct presale end time", async function () {
      const blockTimestamp = (await ethers.provider.getBlock()).timestamp;
      expect(await pFLOTH.presaleEndTime()).to.equal(blockTimestamp + PRESALE_DURATION);
    });
  });

  describe("Presale", function () {
    it("Should revert if presale has ended", async function () {
      const initialTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
      console.log("Initial Timestamp:", initialTimestamp);

      // Increase time by the presale duration plus one second
      await ethers.provider.send("evm_increaseTime", [PRESALE_DURATION + 1]);
      await ethers.provider.send("evm_mine", []);

      const newTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
      console.log("New Timestamp:", newTimestamp);

      // Attempt to participate in the presale after the presale period has ended
      await expect(pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) })).to.be.revertedWith("PresaleEnded");
    });

    it("Should mint the correct amount of pFLOTH tokens", async function () {
      const amountFLR = ethers.parseUnits("1", 18);
      const amountpFLOTH = amountFLR * EXCHANGE_RATE;

      await pFLOTH.connect(addr1).presale({ value: amountFLR });

      expect(await pFLOTH.balanceOf(addr1.address)).to.equal(amountpFLOTH);
      expect(await pFLOTH.totalSupply()).to.equal(amountpFLOTH);
    });

    it("Should revert if minting exceeds MAX_SUPPLY", async function () {
      const amountFLR = MAX_SUPPLY / EXCHANGE_RATE + 1n;
      await expect(pFLOTH.connect(addr1).presale({ value: amountFLR })).to.be.revertedWith("ExceedsSupply");
    });

    it("Should revert if minting exceeds WALLET_LIMIT", async function () {
      const amountFLR = WALLET_LIMIT / EXCHANGE_RATE + 1n;
      await expect(pFLOTH.connect(addr1).presale({ value: amountFLR })).to.be.revertedWith("WalletLimitExceeded");
    });

    it("Should emit Presale event", async function () {
      const amountFLR = ethers.parseUnits("1", 18);
      const amountpFLOTH = amountFLR * EXCHANGE_RATE;

      await expect(pFLOTH.connect(addr1).presale({ value: amountFLR }))
        .to.emit(pFLOTH, "Presale")
        .withArgs(addr1.address, amountFLR, amountpFLOTH);
    });
  });

  describe("Withdraw", function () {
    it("Should allow only the owner to withdraw", async function () {
      await pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) });

      await expect(pFLOTH.connect(addr1).withdraw()).to.be.revertedWith("Ownable: caller is not the owner");

      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

      await pFLOTH.connect(owner).withdraw();

      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);
      expect(finalOwnerBalance).to.be.gt(initialOwnerBalance);
    });

    it("Should emit Withdraw event", async function () {
      await pFLOTH.connect(addr1).presale({ value: ethers.parseUnits("1", 18) });

      await expect(pFLOTH.connect(owner).withdraw()).to.emit(pFLOTH, "Withdraw").withArgs(owner.address, ethers.parseUnits("1", 18));
    });
  });
});
