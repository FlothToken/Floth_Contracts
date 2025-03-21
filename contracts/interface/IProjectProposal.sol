// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "./IProjectProposalEvents.sol";

/**
 * @title IProjectProposal - ProjectProposal contract interface
 * @author Ethereal Labs Ltd
 * @notice Interface for the ProjectProposal functionality
 */
interface IProjectProposal is IAccessControlUpgradeable, IProjectProposalEvents {
    // Core data structures
    struct Proposal {
        uint256 id;
        uint256 roundId;
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer;
        address receiver;
        ProposalState state;
    }
    
    struct Round {
        uint256 id;
        uint256 abstainProposalId;
        uint256 maxFlareAmount;
        uint256 roundStartDatetime;
        uint256 roundRuntime;
        uint256 expectedSnapshotDatetime;
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256[] proposalIds;
        RoundStatus status;
    }
    
    struct Votes {
        uint256 proposalId;
        uint256 voteCount;
    }

    struct UserRoundData {
        uint256 proposalCount;
        bool hasVoted;
        uint256 votingPower;
        uint256 flothPassesOwned;
        Votes[] votedProposals;
    }

    struct RoundData {
        Round round;
        mapping(address => UserRoundData) userRoundData;
    }
    
    // Core functions
    function initialize(address _flothAddress, address _flothPassAddress) external;
    function addProposal(uint256 _amountRequested) external;
    function updateProposalReceiverAddress(uint256 _proposalId, address _newAddress) external;
    function killProposal(uint256 _proposalId) external;
    function addVotesToProposal(uint256 _proposalId, uint256 _voteCount) external;
    function removeVotesFromProposal(uint256 _proposalId) external;
    function removeAllVotesFromAllProposals() external;
    function addRound(uint256 _maxFlareAmount, uint256 _roundRuntime) external;
    function killRound(uint256 _roundId) external;
    function takeSnapshot() external;
    function completeRound() external;
    function setNftMultiplier(uint256 _nftMultiplier) external;
    function claimFunds(uint256 _proposalId) external;
    function updateExpectedSnapshotDatetime(uint256 _roundId, uint256 _newExpectedSnapshotDatetime) external;
    function updateRoundRuntime(uint256 _roundId, uint256 _newRoundRuntime) external;
    
    // View functions
    function getProposals(uint256 _pageNumber, uint256 _pageSize) external view returns (Proposal[] memory);
    function getRounds(uint256 _pageNumber, uint256 _pageSize) external view returns (Round[] memory);
    function getWinningProposalForRound(uint256 _roundId) external view returns (Proposal memory);
    function getRoundStatus(uint256 _roundId) external view returns (RoundStatus);
    function getUserRoundData(uint256 _roundId, address _user) external view returns (
        uint256 proposalCount,
        bool hasVoted,
        uint256 votingPower,
        uint256 flothPassesOwned,
        Votes[] memory votedProposals
    );
    function getVotingPower(address _user, uint256 _roundId) external view returns (uint256);
    function getProposalsByRound(uint256 _roundId) external view returns (Proposal[] memory);
    function getCurrentRound() external view returns (Round memory);
} 