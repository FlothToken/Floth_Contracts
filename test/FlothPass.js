const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("FlothPass Contract", function () {
  let FlothPass, flothPass, owner, addr1, addr2, ftsoV2Consumer, ftsoAddress;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const WITHDRAW_ROLE = ethers.keccak256(ethers.toUtf8Bytes("WITHDRAW_ROLE"));

  const zeroAddress = "0x0000000000000000000000000000000000000000";

  beforeEach(async function () {
    // Mock FtsoV2Interface by deploying a simple mock contract or using a fake address
    const ftsoMockAddress = "0x0000000000000000000000000000000000000001"; // Example mock address

    // Deploy the FTSO contract
    const FTSOFactory = await ethers.getContractFactory("FtsoV2Consumer");
    ftsoV2Consumer = await FTSOFactory.deploy(ftsoMockAddress);
    await ftsoV2Consumer.waitForDeployment();

    ftsoAddress = await ftsoV2Consumer.getAddress();

    // Get contract factories and signers
    FlothPass = await ethers.getContractFactory("FlothPass");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    // Deploy FlothPass contract using deployProxy
    flothPass = await upgrades.deployProxy(FlothPass, [ftsoAddress], { kind: "transparent" });
    await flothPass.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await flothPass.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
      expect(await flothPass.hasRole(ADMIN_ROLE, addr1.address)).to.be.false;
    });

    it("Should initialize the max supply correctly", async function () {
      expect(await flothPass.maxSupply()).to.equal(1000);
    });

    it("Should initialize the withdrawAddress correctly", async function () {
      expect(await flothPass.withdrawAddress()).to.equal("0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739");
    });

    it("Should initialize the _currentBaseURI correctly", async function () {
      expect(await flothPass._currentBaseURI()).to.equal("");
    });

    it("Should initialize the price correctly", async function () {
      expect(await flothPass.usdStartPrice()).to.equal(ethers.parseUnits("50", 18));
    });

    it("Should initialize the priceIncrement correctly", async function () {
      expect(await flothPass.priceIncrement()).to.equal(ethers.parseUnits("50", 18));
    });
  });

  describe("Minting", function () {
    it("Should allow a user to mint an NFT", async function () {
      // Activate the sale
      await flothPass.setSaleActive(true);

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      expect(await flothPass.getNumberMinted()).to.equal(1);
    });

    it("Should revert if the sale is inactive whilst minting.", async function () {
      await expect(flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") })).to.be.revertedWithCustomError(flothPass, "SaleInactive");
    });

    // it("Should revert if the totalMinted + quantity exceeds the max supply", async function () {
    //   await flothPass.setSaleActive(true);

    //   await flothPass.setMintPrice(ethers.parseEther("1"));
    //   await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1") });
    //   await expect(flothPass.connect(addr1).mint(333, { value: ethers.parseEther("333") })).to.be.revertedWithCustomError(
    //     flothPass,
    //     "ExceedsMaxSupply"
    //   );
    // });

    it("Should update the price after every 10 NFTs sold", async function () {
      await flothPass.setSaleActive(true);

      expect(await flothPass.price()).to.equal(ethers.parseEther("1"));

      await flothPass.connect(addr1).mint(9, { value: ethers.parseEther("9") });

      expect(await flothPass.price()).to.equal(ethers.parseEther("1"));

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1") });

      expect(await flothPass.price()).to.equal(ethers.parseEther("1.05"));

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1.05") });
    });

    it("Should revert if user tries to mint without enough funds", async function () {
      await flothPass.setSaleActive(true);

      await expect(flothPass.connect(addr1).mint(1, { value: ethers.parseEther("999") })).to.be.revertedWithCustomError(
        flothPass,
        "InsufficientFunds"
      );
    });
  });

  describe("Transfers", function () {
    it("Should allow a user to transfer an NFT", async function () {
      // Activate the sale
      await flothPass.setSaleActive(true);

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      // Transfer the NFT to addr2
      await flothPass.connect(addr1).transferFrom(addr1.address, addr2.address, 1);

      expect(await flothPass.balanceOf(addr1.address)).to.equal(0);
      expect(await flothPass.balanceOf(addr2.address)).to.equal(1);
    });

    it("Should remove the ownership of an NFT from a user when transferred", async function () {
      // Activate the sale
      await flothPass.setSaleActive(true);

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      // Check if addr1 owns the NFT
      expect(await flothPass.ownerOf(1)).to.equal(addr1.address);
      expect(await flothPass.balanceOf(addr1.address)).to.equal(1);
      const ownedByAddr1 = await flothPass.tokensOfOwner(addr1.address);
      expect(ownedByAddr1.length).to.equal(1);
      expect(ownedByAddr1[0]).to.equal(1);
      const ownedByAddr2 = await flothPass.tokensOfOwner(addr2.address);
      expect(ownedByAddr2.length).to.equal(0);

      // Transfer the NFT to addr2
      await flothPass.connect(addr1).transferFrom(addr1.address, addr2.address, 1);

      // Check if addr1 no longer owns the NFT
      expect(await flothPass.balanceOf(addr1.address)).to.equal(0);
      const newOwnedByAddr1 = await flothPass.tokensOfOwner(addr1.address);
      expect(newOwnedByAddr1.length).to.equal(0);

      //Check if addr2 now owns the NFT
      expect(await flothPass.balanceOf(addr2.address)).to.equal(1);
      const newOwnedByAddr2 = await flothPass.tokensOfOwner(addr2.address);
      expect(newOwnedByAddr2.length).to.equal(1);
      expect(newOwnedByAddr2[0]).to.equal(1);
    });
  });

  describe("Withdrawing", function () {
    it("Should allow withdrawal of native tokens from the FlothPASS contract to the withdrawal address", async function () {
      const flothPassAddress = await flothPass.getAddress();

      await owner.sendTransaction({
        to: flothPassAddress,
        value: ethers.parseEther("1000"),
      });

      const balanceBefore = await ethers.provider.getBalance(flothPassAddress);
      expect(balanceBefore).to.equal(ethers.parseEther("1000"));

      expect(await ethers.provider.getBalance(flothPass.withdrawAddress())).to.equal(0);

      await flothPass.connect(owner).withdraw(ethers.parseEther("1000"), false);

      const balanceAfter = await ethers.provider.getBalance(flothPassAddress);
      expect(balanceAfter).to.equal(0);

      expect(await ethers.provider.getBalance(flothPass.withdrawAddress())).to.equal(ethers.parseEther("1000"));
    });

    it("Should revert when withdrawing flare with insufficient funds in contract", async function () {
      const flothPassAddress = await flothPass.getAddress();

      const [sender] = await ethers.getSigners();
      const tx = await sender.sendTransaction({
        to: flothPassAddress,
        value: ethers.parseUnits("1000", 18), // Sending 1 Ether
      });
      await tx.wait();

      await expect(flothPass.connect(owner).withdraw(ethers.parseUnits("10000", 18), false)).to.be.revertedWithCustomError(
        flothPass,
        "InsufficientFundsInContract"
      );
    });

    it("should call the fallback function", async function () {
      const flothPassAddress = await flothPass.getAddress();
      const [sender] = await ethers.getSigners();

      const tx = await sender.sendTransaction({
        to: flothPassAddress,
        data: "0x12345678", // Random data to trigger fallback
        value: ethers.parseUnits("1000", 18), // Sending 1 Ether
      });
      await tx.wait();

      // Check that the fallback function was called by listening to the event
      await expect(tx).to.emit(flothPass, "FallbackCalled").withArgs(sender.address, ethers.parseUnits("1000", 18), "0x12345678");
    });

    it("Should revert when withdrawing flare with insufficient role", async function () {
      await expect(flothPass.connect(addr1).withdraw(0, true)).to.be.revertedWithCustomError(flothPass, "InsufficientRole");
    });
  });

  describe("Setters and getters", function () {
    // get tokensOfOwner
    it("Should be able to get the tokens of an owner", async function () {
      // Initially, the number of minted passes should be 0
      expect(await flothPass.balanceOf(addr1.address)).to.equal(0);

      // Activate the sale
      await flothPass.setSaleActive(true);

      // Mint a pass from addr1
      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      // Check the number of minted passes for addr1
      expect(await flothPass.balanceOf(addr1.address)).to.equal(1);

      // Check the tokens of addr1
      const ownedTokens = await flothPass.tokensOfOwner(addr1.address);

      expect(ownedTokens.length).to.equal(1);
      // expect(ownedTokens[0]).to.equal(1);
    });

    it("Should be able to get the number of minted passes for an address", async function () {
      // Initially, the number of minted passes should be 0
      expect(await flothPass.balanceOf(addr1.address)).to.equal(0);

      // Activate the sale
      await flothPass.setSaleActive(true);

      // Mint a pass from addr1
      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      // Check the number of minted passes for addr1
      expect(await flothPass.balanceOf(addr1.address)).to.equal(1);
    });

    it("Should allow admins to set the setBaseUri", async function () {
      await flothPass.connect(owner).setBaseUri("https://api.flothpass.com/");

      expect(await flothPass._currentBaseURI()).to.equal("https://api.flothpass.com/");
    });

    it("Should not allow non-admins to set the symbol", async function () {
      await expect(flothPass.connect(addr1).setBaseUri("test")).to.be.revertedWith(
        "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
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
        "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
      );
    });

    it("Should allow admins to set the maxSupply", async function () {
      await flothPass.connect(owner).setMaxSupply(666);

      expect(await flothPass.maxSupply()).to.equal(666);
    });

    // it("Should allow admins to set the mintPrice", async function () {
    //   await flothPass.connect(owner).setMintPrice(ethers.parseUnits("500", 18));

    //   expect(await flothPass.price()).to.equal(ethers.parseUnits("500", 18));
    // });

    // it("Should not allow non-admins to set the mint price", async function () {
    //   await expect(flothPass.connect(addr1).setMintPrice(600)).to.be.revertedWith(
    //     "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
    //   );
    // });

    it("Should allow admins to set the withdrawAddress", async function () {
      const newWithdrawAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";
      await flothPass.connect(owner).setWithdrawAddress(newWithdrawAddress);

      expect(await flothPass.withdrawAddress()).to.equal(newWithdrawAddress);
    });

    it("Should not allow non-admins to set the withdrawAddress", async function () {
      const newWithdrawAddress = "0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739";

      await expect(flothPass.connect(addr1).setWithdrawAddress(newWithdrawAddress)).to.be.revertedWith(
        "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
      );
    });

    it("Should revert if the withdraw address is set to a zero address", async function () {
      await expect(flothPass.connect(owner).setWithdrawAddress(zeroAddress)).to.be.revertedWithCustomError(flothPass, "ZeroAddress");
    });

    it("Should allow admins to set the saleActive", async function () {
      await flothPass.connect(owner).setSaleActive(true);

      expect(await flothPass.saleActive()).to.be.true;
    });

    it("Should not allow non-admins to set the saleActive", async function () {
      await expect(flothPass.connect(addr1).setSaleActive(true)).to.be.revertedWith(
        "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
      );
    });

    it("should return the correct token URI", async function () {
      const baseTokenURI = "https://example.com/token/";

      //Activate the sale
      await flothPass.setSaleActive(true);

      await flothPass.connect(addr1).mint(1, { value: ethers.parseEther("1000") });

      expect(await flothPass.getNumberMinted()).to.equal(1);

      // Set the base URI
      await flothPass.setBaseUri(baseTokenURI);

      // Get the token URI
      const tokenURI = await flothPass.tokenURI(1);
      expect(tokenURI).to.equal(`${baseTokenURI}1`);
    });

    it("should return true for supported interfaces", async function () {
      // ERC721 interface ID
      const ERC721_INTERFACE_ID = "0x80ac58cd";
      // ERC721Enumerable interface ID
      const ERC721_ENUMERABLE_INTERFACE_ID = "0x780e9d63";
      // AccessControl interface ID
      const ACCESS_CONTROL_INTERFACE_ID = "0x7965db0b";

      // Check if the contract supports ERC721 interface
      expect(await flothPass.supportsInterface(ERC721_INTERFACE_ID)).to.equal(true);

      // Check if the contract supports ERC721Enumerable interface
      expect(await flothPass.supportsInterface(ERC721_ENUMERABLE_INTERFACE_ID)).to.equal(true);

      // Check if the contract supports AccessControl interface
      expect(await flothPass.supportsInterface(ACCESS_CONTROL_INTERFACE_ID)).to.equal(true);
    });

    it("should return false for unsupported interfaces", async function () {
      // Random interface ID that is not supported
      const UNSUPPORTED_INTERFACE_ID = "0xffffffff";

      // Check if the contract supports the unsupported interface
      expect(await flothPass.supportsInterface(UNSUPPORTED_INTERFACE_ID)).to.equal(false);
    });
  });

  describe("Upgrades", function () {
    it("Should be able to upgrade the contract", async function () {
      const FlothPassV2 = await ethers.getContractFactory("FlothPassUpgrade");
      const flothPassV2 = await upgrades.upgradeProxy(await flothPass.getAddress(), FlothPassV2);

      expect(await flothPassV2.isContractUpgraded()).to.equal("Contract is upgraded");
    });
  });
});
