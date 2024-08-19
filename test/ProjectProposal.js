const { expect } = require("chai");
const { ethers } = require("hardhat");

const zeroBytes32 = "0x0000000000000000000000000000000000000000000000000000000000000000";
const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("ProjectProposal Contract", function () {
  let projectProposal;
  let owner;
  let floth;
  let flothPass;
  let dexAddress;
  let flothAddress;
  let flothPassAddress;
  let addr1;
  let addr2;
  let currentTime;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const SNAPSHOTTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("SNAPSHOTTER_ROLE"));
  const ROUND_MANAGER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ROUND_MANAGER_ROLE"));

  beforeEach(async function () {
    [owner, addr1, addr2, dexAddress, _] = await ethers.getSigners();

    // Deploy the Floth mock contract
    const FlothFactory = await ethers.getContractFactory("Floth");
    floth = await FlothFactory.deploy([dexAddress.address], "FlothToken", "FLOTH");
    await floth.waitForDeployment();

    flothAddress = await floth.getAddress();

    // Deploy FlothPass contract using deployProxy
    FlothPass = await ethers.getContractFactory("FlothPass");
    flothPass = await upgrades.deployProxy(FlothPass, [flothAddress], { kind: "transparent" });
    await flothPass.waitForDeployment();

    flothPassAddress = await flothPass.getAddress();

    const ProjectProposalFactory = await ethers.getContractFactory("ProjectProposal");
    projectProposal = await upgrades.deployProxy(ProjectProposalFactory, [flothAddress, flothPassAddress], { kind: "transparent" });
    await projectProposal.waitForDeployment();

    const block = await ethers.provider.getBlock("latest");
    currentTime = block.timestamp;
  });

  describe("Deployment", function () {
    it("Should revert when deployed with zero address", async function () {
      const ProjectProposalFactory = await ethers.getContractFactory("ProjectProposal");

      await expect(upgrades.deployProxy(ProjectProposalFactory, [zeroAddress, zeroAddress], { kind: "transparent" })).to.be.revertedWithCustomError(
        ProjectProposalFactory,
        "ZeroAddress"
      );
    });

    it("Should set the correct roles", async function () {
      expect(await projectProposal.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
      expect(await projectProposal.hasRole(ADMIN_ROLE, addr1.address)).to.be.false;
    });

    it("Should set the correct Floth address", async function () {
      expect(await projectProposal.getFlothAddress()).to.equal(flothAddress);
    });
  });

  describe("Proposal Management", function () {
    it("Should allow adding a new proposal", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      const proposal = await projectProposal.getProposalById(2);
      expect(proposal.title).to.equal("Test Proposal");
      expect(proposal.amountRequested).to.equal(ethers.parseUnits("10", 18));
      expect(proposal.proposer).to.equal(addr1.address);
    });

    it("Should revert when adding a proposal with zero amount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).addProposal("Test Proposal", 0)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidAmountRequested"
      );
    });

    it("Should revert when adding a proposal with amount greater than round's maxFlareAmount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("200", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidAmountRequested"
      );
    });

    it("Should allow updating the proposal receiver address", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).setProposalReceiverAddress(2, addr2.address);
      const proposal = await projectProposal.getProposalById(2);
      expect(proposal.receiver).to.equal(addr2.address);
    });

    it("Should allow updating the nftMultiplier", async function () {
      await projectProposal.connect(owner).setNftMultiplier(10);
      const nftMultiplier = await projectProposal.nftMultiplier();
      expect(nftMultiplier).to.equal(10);
    });

    it("Should shouldn't allow non admins to update the nftMultiplier", async function () {
      await expect(projectProposal.connect(addr1).setNftMultiplier(10)).to.be.revertedWith(
        "AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE
      );
    });

    it("Should not allow updating the proposal receiver address if voting period is open", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine", []);

      await projectProposal.takeSnapshot();

      await expect(projectProposal.connect(addr1).setProposalReceiverAddress(1, addr2.address)).to.be.revertedWithCustomError(
        projectProposal,
        "VotingPeriodOpen"
      );
    });

    it("Should revert if non-proposer tries to update proposal receiver address", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await expect(projectProposal.connect(addr2).setProposalReceiverAddress(2, addr2.address)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidPermissions"
      );
    });

    it("Should revert if trying to update proposal receiver address to zero address", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await expect(projectProposal.connect(addr1).setProposalReceiverAddress(2, zeroAddress)).to.be.revertedWithCustomError(
        projectProposal,
        "ZeroAddress"
      );
    });

    it("Should continue with updating proposal receiver address when voting period is open", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7200]);
      await ethers.provider.send("evm_mine");

      //Take snapshot
      await projectProposal.takeSnapshot();

      //Increase EVM time
      await ethers.provider.send("evm_increaseTime", [10000]);
      await ethers.provider.send("evm_mine");

      await expect(projectProposal.connect(addr1).setProposalReceiverAddress(2, addr1.address)).to.not.be.reverted;
    });

    it("Should revert if trying to add a proposal outside submission window", async function () {
      // Simulate passing of submission window
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);
      await expect(projectProposal.connect(addr1).addProposal("Late Proposal", ethers.parseUnits("10", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "SubmissionWindowClosed"
      );
    });

    //TODO: Need to discuss this with Kyle
    // it("Should revert if trying to add a proposal while voting period is open", async function () {
    //   await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
    //     value: ethers.parseUnits("10", 18),
    //   });

    //   //_roundRuntime = 7200
    //   //expectedSnapshotDatetime = currentTime + 3600

    //   await ethers.provider.send("evm_increaseTime", [4000]);
    //   await ethers.provider.send("evm_mine", []);

    //   await expect(projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18))).to.be.revertedWithCustomError(
    //     projectProposal,
    //     "VotingPeriodOpen"
    //   );

    //   // if(latestRound.snapshotDatetime == 0){
    //   //   return (block.timestamp >= latestRound.expectedSnapshotDatetime && block.timestamp <= latestRound.roundStartDatetime + latestRound.roundRuntime);
    // });

    it("Should get all the proposals by address", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Another Proposal", ethers.parseUnits("10", 18));
      const proposals = await projectProposal.getProposalsByAddress(1, addr1.address);
      expect(proposals.length).to.equal(2);
    });

    it("Should revert if proposal ID is out of range", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await expect(projectProposal.getProposalById(3)).to.be.revertedWithCustomError(projectProposal, "ProposalIdOutOfRange");
    });
  });

  describe("Round Management", function () {
    it("Should allow adding a new round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      const round = await projectProposal.getRoundById(1);
      expect(round.id).to.equal(1);
      expect(round.maxFlareAmount).to.equal(ethers.parseUnits("10", 18));
    });

    it("Should revert when trying to add a new round as non-admin", async function () {
      await expect(
        projectProposal.connect(addr1).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
          value: ethers.parseUnits("10", 18),
        })
      ).to.be.revertedWith("AccessControl: account " + addr1.address.toLowerCase() + " is missing role " + ADMIN_ROLE);
    });

    it("Should revert when adding a round with the incorrect flare amount", async function () {
      await expect(
        projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, { value: ethers.parseUnits("1", 18) })
      ).to.be.revertedWithCustomError(projectProposal, "InsufficientFundsForRound");
    });

    it("Should revert when getting round by ID that is bigger than current round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.getRoundById(3)).to.be.revertedWithCustomError(projectProposal, "RoundIdOutOfRange");
    });

    it("Should allow updating round max flare amount", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const isWindowOpen = await projectProposal.isSubmissionWindowOpen();
      expect(isWindowOpen).to.equal(true);

      await projectProposal.increaseRoundMaxFlare({
        value: ethers.parseUnits("1", 18),
      });
      const round = await projectProposal.getRoundById(1);
      console.log("Max flare = " + round.maxFlareAmount);
      expect(round.maxFlareAmount).to.equal(ethers.parseUnits("11", 18));
    });

    it("Should revert when increasing max flare amount if value passed is 0.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const isWindowOpen = await projectProposal.isSubmissionWindowOpen();
      expect(isWindowOpen).to.equal(true);

      await expect(
        projectProposal.connect(owner).increaseRoundMaxFlare({
          value: ethers.parseUnits("0", 18),
        })
      ).to.be.revertedWithCustomError(projectProposal, "InvalidAmountRequested");
    });

    it("Should revert when increasing max flare amount if submission window is closed.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine", []);

      await expect(
        projectProposal.connect(owner).increaseRoundMaxFlare({
          value: ethers.parseUnits("1", 18),
        })
      ).to.be.revertedWithCustomError(projectProposal, "SubmissionWindowClosed");
    });

    it("Should revert if non-manager tries to update round max flare amount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(
        projectProposal.connect(addr1).increaseRoundMaxFlare({
          value: ethers.parseUnits("1", 18),
        })
      ).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });

    it("Should allow taking a snapshot", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime, { value: ethers.parseUnits("10", 18) });
      await projectProposal.takeSnapshot();
      const round = await projectProposal.getRoundById(1);
      expect(round.snapshotBlock).to.be.gt(0);
    });

    it("Should revert if non-manager tries to take a snapshot", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime, { value: ethers.parseUnits("10", 18) });
      await expect(projectProposal.connect(addr1).takeSnapshot()).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });

    it("Should revert if snapshot is taken before expectedSnapshotDatetime", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await expect(projectProposal.connect(owner).takeSnapshot()).to.be.revertedWithCustomError(projectProposal, "InvalidSnapshotTime");
    });

    it("Should revert if snapshot is taken when round is closed", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await ethers.provider.send("evm_increaseTime", [8000]);
      await ethers.provider.send("evm_mine", []);

      await expect(projectProposal.connect(owner).takeSnapshot()).to.be.revertedWithCustomError(projectProposal, "RoundIsClosed");
    });

    it("Should allow killing a round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.killRound(1);
      const round = await projectProposal.getRoundById(1);
      expect(round.isActive).to.equal(false);
    });

    it("Should revert if non-manager tries to kill a round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).killRound(1)).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });

    it("Should extend the round runtime by the correct amount.", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(owner).extendRoundRuntime(7200);
      const latestRound = await projectProposal.rounds(1);
      expect(latestRound.roundRuntime).to.equal(7200);
    });

    it("Should revert if non-manager tries to extend round runtime", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      await expect(projectProposal.connect(addr1).extendRoundRuntime(7200)).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });

    it("Should revert during extend round runtime if the runtime is less than the current runtime.", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 7200, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      await expect(projectProposal.connect(owner).extendRoundRuntime(1800)).to.be.revertedWithCustomError(projectProposal, "InvalidRoundRuntime");
    });

    it("Should revert during extend round runtime if the round is closed.", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(owner).killRound(1);

      await ethers.provider.send("evm_increaseTime", [9000]);
      await ethers.provider.send("evm_mine");

      await expect(projectProposal.connect(owner).extendRoundRuntime(8000)).to.be.revertedWithCustomError(projectProposal, "RoundIsClosed");
    });

    it("Should extend the round expected snapshot time by the correct amount.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const newSnapshotDatetime = currentTime + 3600;
      await projectProposal.connect(owner).extendRoundExpectedSnapshotDatetime(newSnapshotDatetime);

      const latestRound = await projectProposal.rounds(1);

      expect(latestRound.expectedSnapshotDatetime).to.equal(newSnapshotDatetime);
      expect(latestRound.roundRuntime).to.equal(3600);
    });

    it("Should have an extended snapshot datetime in the future", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const newSnapshotDatetime = currentTime - 36000;
      await expect(projectProposal.connect(owner).extendRoundExpectedSnapshotDatetime(newSnapshotDatetime)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidSnapshotTime"
      );
    });

    it("Should have an extended snapshot datetime in the future - alt version", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const newSnapshotDatetime = currentTime + 360000;
      await expect(projectProposal.connect(owner).extendRoundExpectedSnapshotDatetime(newSnapshotDatetime)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidSnapshotTime"
      );
    });

    it("Should revert if non-manager tries to extend round expected snapshot time", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await expect(projectProposal.connect(addr1).extendRoundExpectedSnapshotDatetime(currentTime + 3600)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidPermissions"
      );
    });

    it("Should revert if roundFinished is called and the round isn't over.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      //Add a proposal.
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [40000]);
      await ethers.provider.send("evm_mine");

      await expect(projectProposal.connect(owner).roundFinished()).to.be.revertedWithCustomError(projectProposal, "RoundIsOpen");
    });
  });

  describe("Voting", function () {
    it("Should allow voting on a proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7200]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      await projectProposal.connect(addr1).addVotesToProposal(2, 10);

      const proposal = await projectProposal.proposals(2);
      expect(proposal.votesReceived).to.equal(10);
    });

    it("Should allow for partial FLOTH voting on a proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7200]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 0));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      await projectProposal.connect(addr1).addVotesToProposal(2, 8);

      const proposal = await projectProposal.proposals(2);
      expect(proposal.votesReceived).to.equal(8);

      //Expect remaining voting power to be 2.
      const remainingVotingPower = await projectProposal.getRemainingVotingPower(addr1.address);
      expect(remainingVotingPower).to.equal(2);
    });

    it("Should allow voting on an abstain proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7200]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      //ID 1 is the abstain proposal.
      await projectProposal.connect(addr1).addVotesToProposal(1, 10);

      const proposal = await projectProposal.proposals(1);
      expect(proposal.votesReceived).to.equal(ethers.parseUnits("10", 18));
    });

    it("Should allow voting on an abstain proposal after already voting on another proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7200]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      //First vote for proposal 2.
      await projectProposal.connect(addr1).addVotesToProposal(2, 10);

      //Then vote for abstain proposal.
      await projectProposal.connect(addr1).addVotesToProposal(1, 10);

      const proposal2 = await projectProposal.proposals(2);
      //All votes should be removed from proposal 2.
      expect(proposal2.votesReceived).to.equal(0);
      const proposal = await projectProposal.proposals(1);
      //All votes should be given to abstain.
      expect(proposal.votesReceived).to.equal(ethers.parseUnits("10", 18));
    });

    it("Should remove votes from a proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      await projectProposal.connect(addr1).addVotesToProposal(2, 10);

      const proposalBefore = await projectProposal.proposals(2);
      expect(proposalBefore.votesReceived).to.equal(10);

      await projectProposal.connect(addr1).removeVotesFromProposal(2);

      const proposalAfter = await projectProposal.proposals(2);
      expect(proposalAfter.votesReceived).to.equal(0);
    });

    it("Should remove all votes from all proposals for a user", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal 2", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Test Proposal 3", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Test Proposal 4", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(addr2).addVotesToProposal(3, 20);
      await projectProposal.connect(addr2).addVotesToProposal(4, 25);

      const proposal2Before = await projectProposal.proposals(2);
      expect(proposal2Before.votesReceived).to.equal(10);
      const proposal3Before = await projectProposal.proposals(3);
      expect(proposal3Before.votesReceived).to.equal(20);
      const proposal4Before = await projectProposal.proposals(4);
      expect(proposal4Before.votesReceived).to.equal(25);

      await projectProposal.connect(addr2).removeAllVotesFromAllProposals();

      const proposal2After = await projectProposal.proposals(2);
      expect(proposal2After.votesReceived).to.equal(0);
      const proposal3After = await projectProposal.proposals(3);
      expect(proposal3After.votesReceived).to.equal(0);
      const proposal4After = await projectProposal.proposals(4);
      expect(proposal4After.votesReceived).to.equal(0);
    });

    it("Should revert if voting power is 0", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      await expect(projectProposal.connect(addr1).addVotesToProposal(2, 10)).to.be.revertedWithCustomError(projectProposal, "InvalidVotingPower");
    });

    it("Should revert if user doesn't have enough voting power", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await floth.transfer(addr1.address, ethers.parseUnits("5", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      await expect(projectProposal.connect(addr1).addVotesToProposal(2, ethers.parseUnits("10", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "InsufficientVotingPower"
      );
    });

    it("Should get the correct remaining voting power", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      await floth.transfer(addr2.address, ethers.parseUnits("30", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_mine");

      const power = await projectProposal.getFlothVotingPower(addr2.address);
      console.log("Voting power = " + power.toString());

      //Use 10 votes.
      await projectProposal.connect(addr2).addVotesToProposal(2, ethers.parseUnits("10", 18));

      //Remaining voting power should be 20.
      const remainingVotingPower = await projectProposal.getRemainingVotingPower(addr2.address);
      expect(remainingVotingPower).to.equal(ethers.parseUnits("20", 18));
    });

    it("Should return 0 if getFlothVotingPower is called but a snapshot hasn't been taken", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      await floth.transfer(addr2.address, ethers.parseUnits("30", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await ethers.provider.send("evm_mine");

      const power = await projectProposal.getFlothVotingPower(addr2.address);
      expect(power).to.equal(0);
    });

    it("Should correctly account for a users FLOTH and FlothPass in the voting power.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      // Transfer 4000 Floth tokens to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("4000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("4000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("2000", 18));

      //Delegate addr1 to itself.
      await flothPass.connect(addr1).delegate(addr1.address);

      //Activate sale.
      await flothPass.connect(owner).setSaleActive(true);

      //Mint 2 FlothPass token for addr1. (Spent 2000 Floth).
      await flothPass.connect(addr1).mint(2);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_mine");

      //Check total voting power.
      const totalPower = await projectProposal.getTotalVotingPower(addr1.address);

      const flothPassVotingPower = await projectProposal.getFlothPassVotingPower(addr1.address);

      //Expect flothPassVotingPower = 400;
      expect(flothPassVotingPower).to.equal(400);

      const flothVotingPower = await projectProposal.getFlothVotingPower(addr1.address);

      expect(totalPower).to.equal(flothPassVotingPower + flothVotingPower);
    });

    it("Should revert if trying to remove votes without having voted", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await expect(projectProposal.connect(addr1).removeVotesFromProposal(2)).to.be.revertedWithCustomError(projectProposal, "UserVoteNotFound");
    });

    it("Should get the correct FlothPass voting power", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      // Transfer 4000 Floth tokens to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("4000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("4000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("2000", 18));

      //Activate sale.
      await flothPass.connect(owner).setSaleActive(true);

      //Delegate addr1 to itself.
      await flothPass.connect(addr1).delegate(addr1.address);

      //Mint 2 FlothPass token for addr1. (Spent 2000 Floth).
      await flothPass.connect(addr1).mint(2);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_mine");

      //Check flothpass voting power.
      const flothPassVotingPower = await projectProposal.getFlothPassVotingPower(addr1.address);

      //Expect flothPassVotingPower = 400;
      expect(flothPassVotingPower).to.equal(400);
    });

    it("Should allow voting partial FlothPass voting power to a proposal", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      // Transfer 4000 Floth tokens to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("4000", 18));

      expect(await floth.balanceOf(addr1.address)).to.equal(ethers.parseUnits("4000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("2000", 18));

      //Activate sale.
      await flothPass.connect(owner).setSaleActive(true);

      //Delegate addr1 to itself.
      await flothPass.connect(addr1).delegate(addr1.address);

      //Mint 2 FlothPass token for addr1. (Spent 2000 Floth).
      await flothPass.connect(addr1).mint(2);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_mine");

      //Check flothpass voting power.
      const flothPassVotingPower = await projectProposal.getFlothPassVotingPower(addr1.address);
      expect(flothPassVotingPower).to.equal(400);

      //Vote 200 FlothPass voting power.
      await projectProposal.connect(addr1).addVotesToProposal(2, 200);

      //Check remaining voting power.
      const remainingVotingPower = await projectProposal.getRemainingVotingPower(addr1.address);
      expect(remainingVotingPower).to.equal(200);
    });

    it("Should still have the voting power after a snapshot even when the nft has been sold", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine");

      // Transfer 4000 Floth tokens to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("4000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("2000", 18));

      //Activate sale.
      await flothPass.connect(owner).setSaleActive(true);

      //Delegate addr1 to itself.
      await flothPass.connect(addr1).delegate(addr1.address);

      //Mint 2 FlothPass token for addr1. (Spent 2000 Floth).
      await flothPass.connect(addr1).mint(2);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_mine");

      //Check flothpass voting power.
      const flothPassVotingPower = await projectProposal.getFlothPassVotingPower(addr1.address);

      //Expect flothPassVotingPower = 400 (2 FlothPass tokens * 200 nftmultiplier)
      expect(flothPassVotingPower).to.equal(400);

      //Sell the NFT.
      await flothPass.connect(addr1).transferFrom(addr1.address, addr2.address, 1);

      //Check flothpass voting power still the same.
      const flothPassVotingPowerAfterSale = await projectProposal.getFlothPassVotingPower(addr1.address);

      //Expect flothPassVotingPower = 400;
      expect(flothPassVotingPowerAfterSale).to.equal(400);
    });

    it("Should get total votes for a round", async function () {
      const totalVotes = 32;

      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      //Add 3 proposals.
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send 32 floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("32", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await projectProposal.takeSnapshot();

      //Give 32 votes across proposals.
      await projectProposal.connect(addr1).addVotesToProposal(2, 10);
      await projectProposal.connect(addr1).addVotesToProposal(3, 10);
      await projectProposal.connect(addr1).addVotesToProposal(4, 12);

      const actualVotes = await projectProposal.getTotalVotesForRound(1);

      expect(actualVotes).to.equal(totalVotes);
    });

    it("Should retrieve proposal ID's and the number of votes for each", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Add 2 proposals
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr2).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      //ID 1 is the abstain proposal.
      await projectProposal.connect(addr1).addVotesToProposal(2, 10);
      await projectProposal.connect(addr2).addVotesToProposal(3, 20);

      const voteRetrievals = await projectProposal.connect(owner).voteRetrieval(1, 1, 10);

      expect(voteRetrievals.length).to.equal(3);
    });

    it("Should revert if page size is 0 during vote retrieval", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Add 2 proposals
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr2).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      //ID 1 is the abstain proposal.
      await projectProposal.connect(addr1).addVotesToProposal(2, 10);
      await projectProposal.connect(addr2).addVotesToProposal(3, 20);

      await expect(projectProposal.connect(owner).voteRetrieval(1, 1, 0)).to.be.revertedWithCustomError(projectProposal, "InvalidPageNumberPageSize");
    });

    it("Should revert if page number is 0 during vote retrieval", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Add 2 proposals
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr2).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      //ID 1 is the abstain proposal.
      await projectProposal.connect(addr1).addVotesToProposal(2, 10);
      await projectProposal.connect(addr2).addVotesToProposal(3, 20);

      await expect(projectProposal.connect(owner).voteRetrieval(1, 0, 4)).to.be.revertedWithCustomError(projectProposal, "InvalidPageNumberPageSize");
    });

    it("Should update a users has-voted status to false.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      //Send some floth to addr1.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      // await projectProposal.connect(addr2).addVotesToProposal(3, 10); IF YOU COMMENT THIS IN, THE TEST FAILS, WHICH IS CORRECT.

      const hasVotedBefore = await projectProposal.hasVotedByRound(addr2.address, 1);

      expect(hasVotedBefore).to.equal(true);

      await projectProposal.connect(addr2).removeVotesFromProposal(2);

      const hasVotedAfter = await projectProposal.hasVotedByRound(addr2.address, 1);

      expect(hasVotedAfter).to.equal(false);
    });

    it("Should revert if user votes on a proposal when voting period is not open", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      //Send some floth to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("10", 18));
      await floth.connect(addr1).delegate(addr1.address);

      await expect(projectProposal.connect(addr1).addVotesToProposal(2, 10)).to.be.revertedWithCustomError(projectProposal, "VotingPeriodClosed");
    });
  });

  describe("Claiming Funds", function () {
    it("Should allow the winner to claim funds", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      //Addr2 votes (ID 1 is the abstain proposal)
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();
      //Addr1 claims funds.
      await projectProposal.connect(addr1).claimFunds();
      const proposal = await projectProposal.proposals(2);
      expect(proposal.fundsClaimed).to.be.true;
    });

    it("Should allow the winner to claim funds on the 29th day", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      //Addr2 votes (ID 1 is the abstain proposal)
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //29 days later
      await ethers.provider.send("evm_increaseTime", [86400 * 29]);
      await ethers.provider.send("evm_mine");

      // Check balance of addr1 before claiming funds.
      const balanceBefore = await ethers.provider.getBalance(addr1.address);

      // Addr1 claims funds.
      const tx = await projectProposal.connect(addr1).claimFunds();

      // Check balance of addr1 after claiming funds.
      const balanceAfter = await ethers.provider.getBalance(addr1.address);

      // Calculate the gas cost for the transaction
      const gasUsed = (await tx.wait()).gasUsed;
      const gasPrice = tx.gasPrice;
      const gasCost = gasUsed * gasPrice;

      // Calculate the expected balance after the claim, accounting for gas costs
      const amountRequested = ethers.parseUnits("10", 18);
      const expectedBalanceAfter = balanceBefore + amountRequested - gasCost;

      expect(balanceAfter).to.equal(expectedBalanceAfter);

      const proposal = await projectProposal.proposals(2);
      expect(proposal.fundsClaimed).to.be.true;
    });

    it.only("Should send funds to the grant wallet if abstain wins a round", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("20", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Send some floth to addr2.
      await floth.transfer(addr1.address, ethers.parseUnits("20", 18));
      await floth.connect(addr1).delegate(addr1.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      //Vote for abstain.
      await projectProposal.connect(addr2).addVotesToProposal(1, 10);
      await projectProposal.connect(addr1).addVotesToProposal(2, 9);

      //Check balance of grant wallet.
      const balanceBefore = await ethers.provider.getBalance(await floth.getGrantFundWallet());

      //Round finished.
      await projectProposal.connect(owner).roundFinished();

      //Check balance of grant wallet after round finished.
      const balanceAfter = await ethers.provider.getBalance(await floth.getGrantFundWallet());

      //Verify that the grant wallet received the funds.
      expect(balanceAfter).to.equal(balanceBefore + ethers.parseUnits("10", 18));
    });

    it("Should revert if non-winner tries to claim funds", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();
      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //Addr2 claims funds.
      await expect(projectProposal.connect(addr2).claimFunds()).to.be.revertedWithCustomError(projectProposal, "InvalidClaimer");
    });

    it("Should revert if there is not enough balance when claiming funds", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //Remove funds from address(this).balance
      await ethers.provider.send("hardhat_setBalance", [await projectProposal.getAddress(), "0x0"]);

      await expect(projectProposal.connect(addr1).claimFunds()).to.be.revertedWithCustomError(projectProposal, "InsufficientBalance");
    });

    it("Should revert if the amount requested is more than the claiming funds", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //Remove funds from address(this).balance
      await ethers.provider.send("hardhat_setBalance", [await projectProposal.getAddress(), "0x1"]);

      await expect(projectProposal.connect(addr1).claimFunds()).to.be.revertedWithCustomError(projectProposal, "InsufficientBalance");
    });

    it("Should allow admin to reclaim after 30 days", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();
      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //32 days later
      await ethers.provider.send("evm_increaseTime", [86400 * 32]);
      await ethers.provider.send("evm_mine");

      //Balance of "floth.getGrantFundWallet"
      const balanceBefore = await ethers.provider.getBalance(await floth.getGrantFundWallet());

      await projectProposal.connect(owner).reclaimFunds(1);

      const proposalAfter = await projectProposal.proposals(2);
      expect(proposalAfter.fundsClaimed).to.be.true;

      //Balance after reclaiming funds.
      const balanceAfter = await ethers.provider.getBalance(await floth.getGrantFundWallet());

      //Check balanceAfter = balanceBefore + 10 ether.
      expect(balanceAfter).to.equal(balanceBefore + ethers.parseUnits("10", 18));
    });

    it("Should revert if user tries to claim after 30 days.", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      //Send some floth to addr2.
      await floth.transfer(addr2.address, ethers.parseUnits("10", 18));
      await floth.connect(addr2).delegate(addr2.address);

      //Addr1 adds proposal
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);

      await projectProposal.takeSnapshot();
      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();

      //32 days later
      await ethers.provider.send("evm_increaseTime", [86400 * 32]);

      await expect(projectProposal.connect(addr1).claimFunds()).to.be.revertedWithCustomError(projectProposal, "FundsClaimingPeriodExpired");
    });
  });

  describe("Getters", function () {
    it("Should be able to get the round metadata", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      const { id, expectedSnapshotDatetime, maxFlareAmount, votingWindowEnd, abstainProposalId, latestId, snapshotBlock } =
        await projectProposal.getRoundMetadata(1);
      expect(id).to.equal(1);
      expect(expectedSnapshotDatetime).to.equal(currentTime + 7200);
      expect(maxFlareAmount).to.equal(ethers.parseUnits("10", 18));
      expect(votingWindowEnd).to.be.closeTo(currentTime + 8000, 1);
      expect(abstainProposalId).to.equal(1);
      expect(latestId).to.equal(1);
      expect(snapshotBlock).to.equal(0);
    });

    it("Should revert if getting round metadata for a non-existent round", async function () {
      await expect(projectProposal.getRoundMetadata(1)).to.be.revertedWithCustomError(projectProposal, "RoundIdOutOfRange");
    });

    it("Should revert if roundID is 0", async function () {
      await expect(projectProposal.getRoundMetadata(0)).to.be.revertedWithCustomError(projectProposal, "RoundIdOutOfRange");
    });

    it("Should be able to get all rounds", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      const rounds = await projectProposal.getAllRounds();
      expect(rounds.length).to.equal(1);
    });

    it("Should be able to get all rounds when none exist", async function () {
      const rounds = await projectProposal.getAllRounds();
      expect(rounds.length).to.equal(0);
    });

    it("Should be able to get Floth voting power for an address", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7300]);
      await ethers.provider.send("evm_mine");

      await floth.transfer(addr2.address, ethers.parseUnits("30", 18));
      await floth.connect(addr2).delegate(addr2.address);

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine");

      const power = await projectProposal.getFlothVotingPower(addr2.address);
      expect(power).to.equal(ethers.parseUnits("30", 18));
    });

    it("Should be able to get FlothPass voting power for an address", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      // Transfer 4000 Floth tokens to addr1.
      await floth.transfer(addr1.address, ethers.parseUnits("4000", 18));

      // Approve the FlothPass contract to spend Floth tokens from addr1
      await floth.connect(addr1).approve(await flothPass.getAddress(), ethers.parseUnits("1000", 18));

      //Activate sale.
      await flothPass.connect(owner).setSaleActive(true);

      //Mint 2 FlothPass token for addr1.
      await flothPass.connect(addr1).mint(1);

      await ethers.provider.send("evm_increaseTime", [7300]);
      await ethers.provider.send("evm_mine");

      await projectProposal.takeSnapshot();

      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine");

      const round = await projectProposal.getRoundById(1);
      const snapshotBlock = round.snapshotBlock;

      console.log("Snapshot block = " + snapshotBlock);

      const power = (await projectProposal.flothPassesOwned(snapshotBlock, addr1.address)) * (await projectProposal.nftMultiplier());

      console.log("Power = " + power);

      expect(power).to.equal(1 * 200);
    });

    it("Should return zero Floth voting power if snapshot has not been taken", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      const power = await projectProposal.getFlothVotingPower(addr2.address);
      expect(power).to.equal(0);
    });

    it("Should return zero total voting power if snapshot has not been taken", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });

      const power = await projectProposal.getTotalVotingPower(addr2.address);
      expect(power).to.equal(0);
    });
  });

  describe("Upgrades", function () {
    it("Should be able to upgrade the contract", async function () {
      const ProjectProposalV2 = await ethers.getContractFactory("ProjectProposalUpgrade");
      const projectProposalV2 = await upgrades.upgradeProxy(await projectProposal.getAddress(), ProjectProposalV2);

      expect(await projectProposalV2.isContractUpgraded()).to.equal("Contract is upgraded");
    });
  });
});
