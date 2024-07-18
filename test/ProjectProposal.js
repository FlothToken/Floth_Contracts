const { expect } = require("chai");
const { ethers } = require("hardhat");

const zeroBytes32 = "0x0000000000000000000000000000000000000000000000000000000000000000";
const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("ProjectProposal Contract", function () {
  let projectProposal;
  let owner;
  let floth;
  let dexAddress;
  let flothAddress;
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

    const ProjectProposalFactory = await ethers.getContractFactory("ProjectProposal");
    projectProposal = await ProjectProposalFactory.deploy(flothAddress);
    await projectProposal.waitForDeployment();

    const block = await ethers.provider.getBlock("latest");
    currentTime = block.timestamp;
  });

  describe("Deployment", function () {
    it("Should revert when deployed with zero address", async function () {
      const ProjectProposalFactory = await ethers.getContractFactory("ProjectProposal");

      await expect(ProjectProposalFactory.deploy(zeroAddress)).to.be.revertedWithCustomError(projectProposal, "ZeroAddress");
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
    it("Should revert if trying to add a proposal while voting period is open", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 7200, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      //_roundRuntime = 7200
      //expectedSnapshotDatetime = currentTime + 3600

      await ethers.provider.send("evm_increaseTime", [4000]);
      await ethers.provider.send("evm_mine", []);

      await expect(projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "VotingPeriodOpen"
      );

      // if(latestRound.snapshotDatetime == 0){
      //   return (block.timestamp >= latestRound.expectedSnapshotDatetime && block.timestamp <= latestRound.roundStartDatetime + latestRound.roundRuntime);
    });

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

    it("Should revert if non-manager tries to extend round expected snapshot time", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 3600, currentTime + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      await expect(projectProposal.connect(addr1).extendRoundExpectedSnapshotDatetime(currentTime + 3600)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidPermissions"
      );
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

    //TODO: Not sure why this one isn't receiving the voting power.
    it("Should revert if user doesn't have enough voting power", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await ethers.provider.send("evm_increaseTime", [7500]);
      await ethers.provider.send("evm_mine");

      await floth.transfer(addr1.address, ethers.parseUnits("5", 18));

      await projectProposal.takeSnapshot();

      await expect(projectProposal.connect(addr1).addVotesToProposal(2, 10)).to.be.revertedWithCustomError(
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

      const power = await projectProposal.getVotingPower(addr2.address);
      console.log("Voting power = " + power.toString());

      //Use 10 votes.
      await projectProposal.connect(addr2).addVotesToProposal(2, ethers.parseUnits("10", 18));

      //Remaining voting power should be 20.
      const remainingVotingPower = await projectProposal.getRemainingVotingPower(addr2.address);
      expect(remainingVotingPower).to.equal(ethers.parseUnits("20", 18));
    });

    it("Should revert if trying to remove votes without having voted", async function () {
      await projectProposal.connect(owner).addRound(ethers.parseUnits("10", 18), 8000, currentTime + 7200, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));

      await expect(projectProposal.connect(addr1).removeVotesFromProposal(2)).to.be.revertedWithCustomError(projectProposal, "UserVoteNotFound");
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

      //Addr2 votes
      await projectProposal.connect(addr2).addVotesToProposal(2, 10);
      await projectProposal.connect(owner).roundFinished();
      //Addr1 claims funds.
      await projectProposal.connect(addr1).claimFunds();
      const proposal = await projectProposal.proposals(2);
      expect(proposal.fundsClaimed).to.be.true;
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

      await projectProposal.connect(owner).reclaimFunds(1);

      const proposalAfter = await projectProposal.proposals(2);
      expect(proposalAfter.fundsClaimed).to.be.true;
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
});
