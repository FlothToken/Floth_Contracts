// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IBaseEvents.sol";

/**
 * @title IProjectProposalEvents - ProjectProposal-specific events and errors interface
 * @author Ethereal Labs Ltd
 * @notice Events and errors specific to the ProjectProposal contract
 */
interface IProjectProposalEvents is IBaseEvents {
    // Enums
    enum ProposalState {
        Active,
        Winning,
        Claimed,
        Expired,
        Abstained
    }
    
    enum RoundStatus {
        NotStarted,
        SubmissionOpen,
        SnapshotPending,
        VotingOpen,
        Completed,
        Claimed,
        Expired
    }
    
    // Events
    event ProposalAdded(address creator, uint256 proposalId, uint256 roundId, uint256 amountRequested);
    event ProposalReceiverAddressUpdated(uint256 proposalId, address newAddress);
    event ProposalKilled(uint256 proposalId);
    event RoundAdded(uint256 roundId, uint256 flrAmount, uint256 roundRuntime);
    event RoundCompleted(uint256 roundId, uint256 proposalId);
    event RoundKilled(uint256 roundId);
    event VotesAdded(uint256 proposalId, address wallet, uint256 numberofVotes);
    event VotesRemoved(uint256 proposalId, address wallet, uint256 numberofVotes);
    event AllVotesRemoved(address wallet);
    event SnapshotTaken(uint256 roundId, uint256 snapshotBlock);
    event FundsClaimed(uint256 proposalId, address winningAddress, uint256 amountRequested);
    event FundsReclaimed(uint256 proposalId, address wallet, uint256 amount);
    event FundsNotClaimed(uint256 proposalId, address wallet);
    event expectedSnapshotDatetimeUpdated(uint256 roundId, uint256 newexpectedSnapshotDatetime);
    event RoundRuntimeUpdated(uint256 roundId, uint256 newRoundRuntime);
    event RoundMaxFlareSet(uint256 newMaxFlare);
    event RoundStatusUpdated(uint256 indexed roundId, RoundStatus newStatus);
    
    // Errors
    error InvalidPermissions();
    error SubmissionWindowClosed();
    error VotingPeriodOpen();
    error VotingPeriodClosed();
    error VotingPeriodBeginsSoon();
    error InvalidAmountRequested();
    error InvalidVotingPower();
    error InsufficientVotingPower();
    error InsufficientFundsForRound();
    error FundsAlreadyClaimed();
    error FundsClaimingPeriodExpired();
    error InvalidClaimer();
    error ClaimerNotRecipient();
    error NoProposalsInRound();
    error RoundIsOpen();
    error RoundIsClosed();
    error RoundNotStarted();
    error SubmissionWindowOpen();
    error SnapshotIsNotPending();
    error SnapshotAlreadyTaken();
    error InvalidSnapshotTime();
    error UserVoteNotFound();
    error ProposalIdOutOfRange();
    error RoundIdOutOfRange();
    error InvalidAbstainVote();
    error InvalidRoundRuntime();
    error InvalidPageNumberPageSize();
} 