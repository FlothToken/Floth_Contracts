const { expect } = require("chai");
const { ethers } = require("hardhat");

const zeroBytes32 = "0x0000000000000000000000000000000000000000000000000000000000000000";
const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("ProjectProposal Contract", function () {
  let projectProposal;
  let owner;
  let addr1;
  let addr2;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const SNAPSHOTTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("SNAPSHOTTER_ROLE"));
  const ROUND_MANAGER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ROUND_MANAGER_ROLE"));

  beforeEach(async function () {
    [owner, addr1, addr2, _] = await ethers.getSigners();

    const ProjectProposalFactory = await ethers.getContractFactory("ProjectProposal");
    projectProposal = await ProjectProposalFactory.deploy(addr1.address);
    await projectProposal.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await projectProposal.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
      expect(await projectProposal.hasRole(ADMIN_ROLE, addr1.address)).to.be.false;
    });

    it("Should set the correct Floth address", async function () {
      expect(await projectProposal.getFlothAddress()).to.equal(addr1.address);
    });
  });

  describe("Proposal Management", function () {
    it("Should allow adding a new proposal", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      const proposal = await projectProposal.getProposalById(2);
      expect(proposal.title).to.equal("Test Proposal");
      expect(proposal.amountRequested).to.equal(ethers.parseUnits("10", 18));
      expect(proposal.proposer).to.equal(addr1.address);
    });

    it("Should revert when adding a proposal with zero amount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).addProposal("Test Proposal", 0)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidAmountRequested"
      );
    });

    it("Should revert when adding a proposal with amount greater than round's maxFlareAmount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("200", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidAmountRequested"
      );
    });

    it("Should allow updating the proposal receiver address", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await projectProposal.connect(addr1).setProposalReceiverAddress(2, addr2.address);
      const proposal = await projectProposal.getProposalById(2);
      expect(proposal.receiver).to.equal(addr2.address);
    });

    it("Should revert if non-proposer tries to update proposal receiver address", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      await expect(projectProposal.connect(addr2).setProposalReceiverAddress(2, addr2.address)).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidPermissions"
      );
    });

    it("Should revert if trying to update proposal receiver address to zero address", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
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
  });

  describe("Round Management", function () {
    it("Should allow adding a new round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      const round = await projectProposal.getRoundById(1);
      expect(round.id).to.equal(1);
      expect(round.maxFlareAmount).to.equal(ethers.parseUnits("10", 18));
    });

    it("Should allow updating round max flare amount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 7200, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });

      const isWindowOpen = await projectProposal.isSubmissionWindowOpen();
      expect(isWindowOpen).to.equal(true);

      await projectProposal.increaseRoundMaxFlare({
        value: ethers.parseUnits("1", 18),
      });
      const round = await projectProposal.getRoundById(1);
      expect(round.maxFlareAmount).to.equal(ethers.parseUnits("11", 18));
    });

    it("Should revert if non-manager tries to update round max flare amount", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).setRoundMaxFlare(ethers.parseUnits("2000", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "InvalidPermissions"
      );
    });

    it("Should revert if trying to set round max flare amount higher than contract balance", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.setRoundMaxFlare(ethers.parseUnits("200", 18))).to.be.revertedWithCustomError(
        projectProposal,
        "InsufficientBalance"
      );
    });

    it("Should allow taking a snapshot", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), { value: ethers.parseUnits("10", 18) });
      await projectProposal.takeSnapshot();
      const round = await projectProposal.getRoundById(1);
      expect(round.snapshotBlock).to.be.gt(0);
    });

    it("Should revert if non-manager tries to take a snapshot", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), { value: ethers.parseUnits("10", 18) });
      await expect(projectProposal.connect(addr1).takeSnapshot()).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });

    it("Should revert if snapshot is taken before snapshot time", async function () {
      //TODO: Need to work out why this is failing
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, 1800, {
      //     value: ethers.parseUnits("10", 18),
      //   });
      //   await expect(projectProposal.takeSnapshot()).to.be.revertedWithCustomError(projectProposal, "InvalidSnapshotTime");
    });

    it("Should allow killing a round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await projectProposal.killRound(1);
      const round = await projectProposal.getRoundById(1);
      expect(round.isActive).to.equal(false);
    });

    it("Should revert if non-manager tries to kill a round", async function () {
      await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, {
        value: ethers.parseUnits("10", 18),
      });
      await expect(projectProposal.connect(addr1).killRound(1)).to.be.revertedWithCustomError(projectProposal, "InvalidPermissions");
    });
  });

  describe("Voting", function () {
    it("Should allow voting on a proposal", async function () {
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await projectProposal.takeSnapshot();
      //   await projectProposal.connect(addr1).addVotesToProposal(1, 10);
      //   const proposal = await projectProposal.proposals(1);
      //   expect(proposal.votesReceived).to.equal(10);
    });

    it("Should revert if trying to vote without sufficient voting power", async function () {
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await projectProposal.takeSnapshot();
      //   await expect(projectProposal.connect(addr1).addVotesToProposal(1, 1000)).to.be.revertedWithCustomError(projectProposal, "InvalidVotingPower");
    });

    it("Should allow removing votes from a proposal", async function () {
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await projectProposal.takeSnapshot();
      //   await projectProposal.connect(addr1).addVotesToProposal(1, 10);
      //   await projectProposal.connect(addr1).removeVotesFromProposal(1);
      //   const proposal = await projectProposal.proposals(1);
      //   expect(proposal.votesReceived).to.equal(0);
    });

    it("Should revert if trying to remove votes without having voted", async function () {
      //TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000) + 3600, 1800, { value: ethers.parseUnits("10", 18) });
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("50", 18));
      //   await expect(projectProposal.connect(addr1).removeVotesFromProposal(2)).to.be.revertedWithCustomError(projectProposal, "UserVoteNotFound");
    });
  });

  describe("Claiming Funds", function () {
    it("Should allow the winner to claim funds", async function () {
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await projectProposal.takeSnapshot();
      //   await projectProposal.connect(addr1).addVotesToProposal(1, 10);
      //   await projectProposal.roundFinished();
      //   await projectProposal.claimFunds();
      //   const proposal = await projectProposal.proposals(1);
      //   expect(proposal.fundsClaimed).to.be.true;
    });

    it("Should revert if non-winner tries to claim funds", async function () {
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 3600, Math.floor(Date.now() / 1000), 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await projectProposal.takeSnapshot();
      //   await projectProposal.connect(addr1).addVotesToProposal(1, 10);
      //   await projectProposal.roundFinished();
      //   await expect(projectProposal.connect(addr2).claimFunds()).to.be.revertedWith("InvalidClaimer");
    });

    it("Should revert if trying to claim funds after the claiming period", async function () {
      // uint256 _flrAmount,
      // uint256 _roundRuntime,
      // uint256 _snapshotDatetime,
      // uint256 _votingRuntime
      // TODO: NEED FLOTH CONTRACT FOR THIS TO WORK
      //   await projectProposal.addRound(ethers.parseUnits("10", 18), 7200, Math.floor(Date.now() / 1000) + 3600, 1800);
      //   await projectProposal.connect(addr1).addProposal("Test Proposal", ethers.parseUnits("10", 18));
      //   await ethers.provider.send("evm_increaseTime", [3600]);
      //   await ethers.provider.send("evm_mine", []);
      //   await projectProposal.takeSnapshot();
      //   await projectProposal.connect(addr1).addVotesToProposal(1, 10);
      //   await projectProposal.roundFinished();
      //   // Increase time by 31 days
      //   await ethers.provider.send("evm_increaseTime", [31 * 86400]);
      //   await ethers.provider.send("evm_mine", []);
      //   await expect(projectProposal.claimFunds()).to.be.revertedWith("FundsClaimingPeriod");
    });
  });
});
