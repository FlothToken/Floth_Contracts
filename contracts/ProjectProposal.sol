// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
import "./IFloth.sol";
import "./IFlothPass.sol";

/**
 * @title ProjectProposal contract for the Floth protocol
 * @author Ethereal Labs Ltd
 */
contract ProjectProposal is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Define roles for the contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");
    bytes32 public constant ROUND_MANAGER_ROLE = keccak256("ROUND_MANAGER_ROLE");

    // Define the Floth interface
    IFloth internal floth;

    // Define the FlothPass interface
    IFlothPass internal flothPass;

    //The multiplier constant for holding a FlothPass.
    uint256 public nftMultiplier;

    // Gap for upgradeability
    uint256[50] private __gap;

    /**
     * @dev Initialize the contract
     * @param _flothAddress The address of the Floth contract
     * @param _flothPassAddress The address of the FlothPass contract
     */
    function initialize(address _flothAddress, address _flothPassAddress) public initializer {
        __AccessControl_init();
        __ProjectProposal_init(_flothAddress, _flothPassAddress);
    }

    /**
     * Initializer for the ProjectProposal contract
     * @param _flothAddress The address of the Floth contract
     * @param _flothPassAddress The address of the FlothPass contract
     */

    function __ProjectProposal_init(address _flothAddress, address _flothPassAddress) internal initializer {
        if (_flothAddress == address(0) || _flothPassAddress == address(0)) {
            revert ZeroAddress();
        }
        floth = IFloth(_flothAddress);
        flothPass = IFlothPass(_flothPassAddress);

        nftMultiplier = 50_000_000;

        _setRoleAdmin(SNAPSHOTTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ROUND_MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // TODO Change address when we deploy
        _grantRole(ADMIN_ROLE, msg.sender); // TODO Change address when we deploy
    }

    /**
     * @dev Constructor prevents the contract from being initialized again
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Add this enum before the Proposal struct
    enum ProposalState {
        Active,     // Initial state when proposal is created
        Winning,    // Proposal has won but funds not claimed
        Claimed,    // Funds have been claimed
        Expired,    // Claiming period expired (>30 days)
        Abstained   // Was the abstain proposal
    }

    // Proposal struct to store proposal data
    struct Proposal {
        uint256 id;
        uint256 roundId; //Tracked for claiming funds.
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer; //The wallet that submitted the proposal.
        address receiver; //The wallet that will receive the funds.
        ProposalState state;  // Replace fundsClaimed with state
    }

    
    // Add round status enum
    enum RoundStatus {
        NotStarted,     // Initial state when round is created
        SubmissionOpen, // Proposals can be submitted
        VotingOpen,     // Voting is active (after snapshot)
        Completed,      // Round finished (voting ended)
        Claimed,        // Winner has claimed funds
        Expired        // Round expired (>30 days) or killed
    }

    // Round struct to store round data
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

    //Used to return proposal ids and their vote count for a specific round. And used for votedOnProposals mapping.
    struct Votes {
        uint256 proposalId;
        uint256 voteCount;
    }

    //Tracks ID number for each proposal.
    uint256 public proposalId;

    //Tracks ID number for each round.
    uint256 public roundId;

    // Core data structures
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

    // Core mappings
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => RoundData) public roundData;
    mapping(uint256 => Proposal) public winningProposalByRoundId;
    mapping(address => bool) public hasWinningProposal;
    mapping(address => Proposal[]) public winningProposals;

    /**
     * Events for the ProjectProposal contract
     */
    event ProposalAdded(
        address creator,
        uint256 proposalId,
        uint256 roundId,
        uint256 amountRequested
    );
    event ProposalReceiverAddressUpdated(
        uint256 proposalId,
        address newAddress
    );
    event ProposalKilled(uint256 proposalId);
    event RoundAdded(uint256 roundId, uint256 flrAmount, uint256 roundRuntime);
    event RoundCompleted(uint256 roundId, uint256 proposalId);
    event RoundKilled(uint256 roundId);
    event VotesAdded(uint256 proposalId, address wallet, uint256 numberofVotes);
    event VotesRemoved(
        uint256 proposalId,
        address wallet,
        uint256 numberofVotes
    );
    event AllVotesRemoved(address wallet);
    event SnapshotTaken(uint256 roundId, uint256 snapshotBlock);
    event FundsClaimed(
        uint256 proposalId,
        address winningAddress,
        uint256 amountRequested
    );
    event FundsReclaimed(uint256 proposalId, address wallet, uint256 amount);
    event FundsNotClaimed(uint256 proposalId, address wallet);
    event expectedSnapshotDatetimeUpdated(
        uint256 roundId,
        uint256 newexpectedSnapshotDatetime
    );
    event RoundRuntimeUpdated(uint256 roundId, uint256 newRoundRuntime);
    event RoundMaxFlareSet(uint256 newMaxFlare);
    event RoundStatusUpdated(uint256 indexed roundId, RoundStatus newStatus);

    /**
     * Error messages for the ProjectProposal contract
     */
    error InvalidPermissions();
    error SubmissionWindowClosed();
    error VotingPeriodOpen();
    error VotingPeriodClosed();
    error VotingPeriodBeginsSoon();
    error InvalidAmountRequested();
    error InvalidVotingPower();
    error InsufficientVotingPower();
    error InsufficientBalance();
    error InsufficientFundsForRound();
    error FundsAlreadyClaimed();
    error FundsClaimingPeriodExpired();
    error InvalidClaimer();
    error ClaimerNotRecipient();
    error NoProposalsInRound();
    error RoundIsOpen();
    error RoundIsClosed();
    error InvalidSnapshotTime();
    error UserVoteNotFound();
    error ZeroAddress();
    error ProposalIdOutOfRange();
    error RoundIdOutOfRange();
    error InvalidAbstainVote();
    error InvalidRoundRuntime();
    error InvalidPageNumberPageSize();
    error TransferFailed();

    //Modifiers for the ProjectProposal contract
    modifier roundManagerOrAdmin() {
        if (
            !hasRole(ROUND_MANAGER_ROLE, msg.sender) && // Check if user does not have ROUND_MANAGER_ROLE
            !hasRole(ADMIN_ROLE, msg.sender) // Check if user does not have ADMIN_ROLE
        ) {
            revert InvalidPermissions();
        }
        _;
    }

    modifier managerOrAdmin() {
        if (
            !hasRole(SNAPSHOTTER_ROLE, msg.sender) && // Check if user does not have SNAPSHOTTER_ROLE
            !hasRole(ROUND_MANAGER_ROLE, msg.sender) && // Check if user does not have ROUND_MANAGER_ROLE
            !hasRole(ADMIN_ROLE, msg.sender) // Check if user does not have ADMIN_ROLE
        ) {
            revert InvalidPermissions();
        }
        _;
    }

    /**
     * Function to add a proposal to the contract
     * @param _amountRequested The amount requested for the proposal
     */
    function addProposal(
        uint256 _amountRequested
    ) external {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage latestRound = currentRoundData.round;
        RoundStatus status = getRoundStatus(latestRound.id);

        if (status != RoundStatus.SubmissionOpen) {
            revert SubmissionWindowClosed();
        }

        if (latestRound.maxFlareAmount < _amountRequested || _amountRequested == 0) {
            revert InvalidAmountRequested();
        }

        proposalId++;
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.roundId = latestRound.id;
        newProposal.amountRequested = _amountRequested;
        newProposal.receiver = msg.sender; //receiver set to msg.sender by default.
        newProposal.proposer = msg.sender;
        newProposal.state = ProposalState.Active;

        latestRound.proposalIds.push(proposalId);
        currentRoundData.userRoundData[msg.sender].proposalCount++;
        
        emit ProposalAdded(msg.sender, proposalId, latestRound.id, _amountRequested);
    }

    /**
     * Function to set how much multiplier to use for a FlothPass' voting power.
     * @param _nftMultiplier The multiplier for the NFT voting power.
     */
    function setNftMultiplier(uint256 _nftMultiplier) external onlyRole(ADMIN_ROLE) {
        nftMultiplier = _nftMultiplier;
    }

    /**
     * Function to update the receiver address of a proposal
     * @param _proposalId The ID of the proposal
     * @param _newAddress The new address of the receiver
     */
    function setProposalReceiverAddress(
        uint256 _proposalId,
        address _newAddress
    ) external {
        Proposal storage proposalToUpdate = proposals[_proposalId];
        RoundStatus status = getRoundStatus(proposalToUpdate.roundId);

        if (status == RoundStatus.Completed || 
            status == RoundStatus.Claimed || 
            status == RoundStatus.Expired) {
            revert RoundIsClosed();
        }

        if (status == RoundStatus.VotingOpen) {
            revert VotingPeriodOpen();
        }

        //Only proposer can update receiver address.
        if (msg.sender != proposalToUpdate.proposer) {
            revert InvalidPermissions();
        }

        if (_newAddress == address(0)) {
            revert ZeroAddress();
        }

        proposalToUpdate.receiver = _newAddress;
        emit ProposalReceiverAddressUpdated(_proposalId, _newAddress);
    }

    /**
     * Function to get all proposals for a specific round for a specific address
     * @param _roundId The ID of the round
     * @param _account The address of the account
     */
    function getProposalsByAddress(
        uint256 _roundId,
        address _account
    ) public view returns (Proposal[] memory) {
        RoundData storage roundData_ = roundData[_roundId];
        uint256 count = roundData_.userRoundData[_account].proposalCount;
        Proposal[] memory accountProposals = new Proposal[](count);
        
        uint256 currentIndex = 0;  // Tracks actual position in accountProposals

        for (uint256 i = 0; i < roundData_.round.proposalIds.length; i++) {
            Proposal memory proposal = proposals[roundData_.round.proposalIds[i]];
            if (proposal.proposer == _account) {
                accountProposals[currentIndex] = proposal;
                currentIndex++;
            }
        }
        return accountProposals;
    }

    /**
     * Get a specific proposal by ID
     * @param _id The ID of the proposal
     */
    function getProposalById(
        uint256 _id
    ) public view returns (Proposal memory) {
        if (_id > proposalId) {
            revert ProposalIdOutOfRange();
        }
        return proposals[_id];
    }

    /**
     * Function to add votes to a proposal
     * @param _proposalId The ID of the proposal
     * @param _numberOfVotes The number of votes to add
     */
    function addVotesToProposal(
        uint256 _proposalId,
        uint256 _numberOfVotes
    ) external {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage getRound = currentRoundData.round;
        RoundStatus status = getRoundStatus(getRound.id);
        UserRoundData storage userData = currentRoundData.userRoundData[msg.sender];

        if(status != RoundStatus.VotingOpen) {
            if(status == RoundStatus.SubmissionOpen && 
               block.timestamp > getRound.expectedSnapshotDatetime && 
               getRound.snapshotDatetime == 0) {
                revert VotingPeriodBeginsSoon();
            } else {
                revert VotingPeriodClosed();
            }
        }

        Proposal storage proposal = proposals[_proposalId];

        // Get initial voting power only if they haven't voted yet
        if(!userData.hasVoted){
            userData.votingPower = getFlothVotingPower(msg.sender) + getFlothPassVotingPower(msg.sender);
        }

        // Handle abstain votes
        if (_proposalId == getRound.abstainProposalId) {
            uint256 totalRemovedVotes = 0;

            // Remove votes from previous proposals
            if(userData.votedProposals.length > 0){
                for (uint256 i = 0; i < userData.votedProposals.length; i++) {
                    uint256 voteCount = userData.votedProposals[i].voteCount;
                    uint256 votedProposalId = userData.votedProposals[i].proposalId;
                    proposals[votedProposalId].votesReceived -= voteCount;
                    totalRemovedVotes += voteCount;
                    
                    // Emit event for removed votes
                    emit VotesRemoved(proposalId, msg.sender, voteCount);
                }
            }

            // Clear votes array without using delete
            userData.votedProposals = new Votes[](0);
            
            // Use original voting power for abstain
            uint256 abstainVotes = userData.votingPower + totalRemovedVotes;
            proposal.votesReceived += abstainVotes;
            userData.votingPower = 0;
            userData.hasVoted = true;

            // Add abstain vote to user's votes
            userData.votedProposals.push(Votes({
                proposalId: _proposalId,
                voteCount: abstainVotes
            }));

            emit VotesAdded(_proposalId, msg.sender, abstainVotes);
        } else {
            //Check if the user doesn't have any voting power set, revert. Checked here to let users call abstain if no power left.
            if (userData.votingPower == 0) {
                revert InvalidVotingPower();
            } 
            
            //If the user doesn't have enough voting power, stop them from voting.
            if (userData.votingPower < _numberOfVotes) {
                revert InsufficientVotingPower();
            }

            proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.
            userData.votingPower -= _numberOfVotes; //Reduce voting power in a round.
            userData.hasVoted = true; //Set that the user has voted in a round.

            userData.votedProposals.push(Votes({
                proposalId: _proposalId,
                voteCount: _numberOfVotes
            }));

            emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
        }
    }

    /**
     * Function to remove votes from a proposal
     * @param _proposalId The ID of the proposal
     */
    function removeVotesFromProposal(uint256 _proposalId) external {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage currentRound = currentRoundData.round;
        UserRoundData storage userData = currentRoundData.userRoundData[msg.sender];
        RoundStatus status = getRoundStatus(currentRound.id);

        if (status != RoundStatus.VotingOpen) {
            revert VotingPeriodClosed();
        }

        //Check if the user hasn't voted.
        if (!userData.hasVoted) {
            revert UserVoteNotFound();
        }

        Votes[] storage userVotes = userData.votedProposals;
        for (uint256 i = 0; i < userVotes.length; i++) {
            if(_proposalId == userVotes[i].proposalId) {
                uint256 votesToRemove = userVotes[i].voteCount;

                Proposal storage proposal = proposals[_proposalId];
                
                proposal.votesReceived -= votesToRemove;
                userData.votingPower += votesToRemove;

                // Remove the struct.
                userVotes[i] = userVotes[userVotes.length - 1];
                userVotes.pop();

                if(userVotes.length == 0) {
                    userData.hasVoted = false; //Remove users has voted status.
                }

                emit VotesRemoved(_proposalId, msg.sender, votesToRemove);
                break; //Don't need to continue looping through the struct array.
            }
        }
    }

    /**
     * Function for a user to remove all their votes from all proposals that they have voted on.
     */
    function removeAllVotesFromAllProposals() external {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage currentRound = currentRoundData.round;
        UserRoundData storage userData = currentRoundData.userRoundData[msg.sender];
        RoundStatus status = getRoundStatus(currentRound.id);

        if (status != RoundStatus.VotingOpen) {
            revert VotingPeriodClosed();
        }

        //Check if the user hasn't voted.
        if (!userData.hasVoted) {
            revert UserVoteNotFound();
        }

        Votes[] storage userVotes = userData.votedProposals;
        for (uint256 i = 0; i < userVotes.length; i++) {
            uint256 votesToRemove = userVotes[i].voteCount;
            Proposal storage proposal = proposals[userVotes[i].proposalId];
            proposal.votesReceived -= votesToRemove; //Remove votes given to proposal.
            userData.votingPower += votesToRemove; //Give voting power back to user.
        }

        // Clear the votes mapping.
        delete userData.votedProposals;
        userData.hasVoted = false;

        emit AllVotesRemoved(msg.sender);
    }

    /**
     * Function to add a new round to the contract
     * @param _maxFlareAmount The amount of FLR for the round
     * @param _roundRuntime The runtime of the round
     * @param _expectedSnapshotDatetime The snapshot datetime of the round
     */
    function addRound(
        uint256 _maxFlareAmount,
        uint256 _roundRuntime,
        uint256 _expectedSnapshotDatetime
    ) external payable onlyRole(ADMIN_ROLE) {
        if (msg.value < _maxFlareAmount) {
            revert InsufficientFundsForRound();
        }

        roundId++;
        RoundData storage newRoundData = roundData[roundId];
        Round storage newRound = newRoundData.round;
        newRound.id = roundId;
        newRound.maxFlareAmount = _maxFlareAmount;
        newRound.roundStartDatetime = block.timestamp;
        newRound.roundRuntime = _roundRuntime;
        newRound.expectedSnapshotDatetime = _expectedSnapshotDatetime;
        newRound.snapshotBlock = 0;
        newRound.snapshotDatetime = 0; 
        newRound.status = RoundStatus.NotStarted;  // Set initial status

        //Add 'Abstain' proposal for the new round.
        proposalId++;
        Proposal storage abstainProposal = proposals[proposalId];
        abstainProposal.id = proposalId;
        abstainProposal.roundId = roundId;
        abstainProposal.amountRequested = 0;
        abstainProposal.receiver = msg.sender;
        abstainProposal.proposer = msg.sender;
        abstainProposal.state = ProposalState.Active;  // Set initial state

        newRound.proposalIds.push(proposalId); //Add abstain proposal to round struct.
        newRound.abstainProposalId = proposalId; //Used to track the abstain proposal of the round.

        emit RoundAdded(roundId, _maxFlareAmount, _roundRuntime);
        emit RoundStatusUpdated(roundId, RoundStatus.NotStarted);
    }

    /**
     * Function to increase the max flare amount for a round
     */
    function increaseRoundMaxFlare() external payable roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();
        RoundStatus status = getRoundStatus(roundToUpdate.id);

        if (msg.value == 0) {
            revert InvalidAmountRequested();
        }

        if (status != RoundStatus.SubmissionOpen) {
            revert SubmissionWindowClosed();
        }

        roundToUpdate.maxFlareAmount += msg.value;
        emit RoundMaxFlareSet(roundToUpdate.maxFlareAmount);
    }

    /**
     * Function to extend the runtime of a round
     * @param _newRoundRuntime The new runtime for the round
     */
    function extendRoundRuntime(uint256 _newRoundRuntime) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();
        RoundStatus status = getRoundStatus(roundToUpdate.id);

        // Ensure the new runtime is greater than the current round runtime
        if (_newRoundRuntime <= roundToUpdate.roundRuntime) {
            revert InvalidRoundRuntime();
        }

        if (status == RoundStatus.Completed || 
            status == RoundStatus.Claimed || 
            status == RoundStatus.Expired) {
            revert RoundIsClosed();
        }

        // Update the round runtime
        roundToUpdate.roundRuntime = _newRoundRuntime;

        // Emit an event for updating the round runtime
        emit RoundRuntimeUpdated(roundId, _newRoundRuntime);
    }

    /**
     * Function to change the snapshot datetime of a round to a future datetime
     * @param _newExpectedSnapshotDatetime The extended time to add to snapshot datetime and round runtime for the round
     */
    function extendRoundExpectedSnapshotDatetime(uint256 _newExpectedSnapshotDatetime) external managerOrAdmin {
        Round storage roundToUpdate = getLatestRound();
        RoundStatus status = getRoundStatus(roundToUpdate.id);

        // Ensure round isn't finished
        if (status == RoundStatus.Completed || 
            status == RoundStatus.Claimed || 
            status == RoundStatus.Expired) {
            revert RoundIsClosed();
        }

        // Add check to prevent extending after snapshot is taken
        if (status == RoundStatus.VotingOpen) {
            revert VotingPeriodOpen();
        }

        // Ensure the new snapshot time is in the future and within the round runtime
        if (
            block.timestamp >= _newExpectedSnapshotDatetime ||
            _newExpectedSnapshotDatetime >
            (roundToUpdate.roundStartDatetime + roundToUpdate.roundRuntime)
        ) {
            revert InvalidSnapshotTime();
        }

        // Calculate the difference in time
        uint256 timeDifference = _newExpectedSnapshotDatetime -
            roundToUpdate.expectedSnapshotDatetime;

        // Update the snapshot datetime
        roundToUpdate.expectedSnapshotDatetime = _newExpectedSnapshotDatetime;

        // Adjust the round end time and voting window by the same amount of time
        roundToUpdate.roundRuntime += timeDifference;

        // Emit events for updating the snapshot datetime and round runtime
        emit expectedSnapshotDatetimeUpdated(roundId, _newExpectedSnapshotDatetime);
        emit RoundRuntimeUpdated(roundId, roundToUpdate.roundRuntime);
    }

    /**
     * Function to take a snapshot of the current block
     */
    function takeSnapshot() external managerOrAdmin {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage round = currentRoundData.round;
        RoundStatus status = getRoundStatus(round.id);

        if (status == RoundStatus.Completed || 
            status == RoundStatus.Claimed || 
            status == RoundStatus.Expired) {
            revert RoundIsClosed();
        }

        if (status != RoundStatus.SubmissionOpen) {
            revert InvalidSnapshotTime();
        }

        if(round.snapshotBlock == 0){
            round.snapshotBlock = block.number;
            round.snapshotDatetime = block.timestamp; //Set the actual snapshot time.
            _getFlothPassesOwned(round.snapshotBlock); //Takes a snapshot of the FlothPasses owned.
            round.status = RoundStatus.VotingOpen;
            emit RoundStatusUpdated(round.id, RoundStatus.VotingOpen);
        }

        emit SnapshotTaken(round.id, round.snapshotBlock);
    }

    function _getFlothPassesOwned(uint256 _snapshotBlock) internal {
        RoundData storage currentRoundData = roundData[roundId];
        uint256 totalSupply = flothPass.totalSupply(); //TODO add totalSupply method.
        
        for (uint256 i = 0; i < totalSupply; i++) {
            address owner = flothPass.ownerOf(i + 1);
            uint256 votingPower = flothPass.getPastVotes(owner, _snapshotBlock);
            if (votingPower > 0) {
                UserRoundData storage userData = currentRoundData.userRoundData[owner];
                userData.flothPassesOwned = votingPower;
            }
        }
    }

    /**
     * Function to get the total votes for a round
     */
    function getTotalVotesForRound(uint256 _roundId) external view returns (uint256) {
        RoundData storage roundData_ = roundData[_roundId];
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < roundData_.round.proposalIds.length; i++) {
            totalVotes += proposals[roundData_.round.proposalIds[i]].votesReceived;
        }
        return totalVotes;
    }

    /**
     * Get a round given a particular id
     * @param _id The ID of the round
     */
    function getRoundById(uint256 _id) public view returns (Round memory) {
        if (_id > roundId) {
            revert RoundIdOutOfRange();
        }
        return roundData[_id].round;
    }

    /**
     * Get the metadata for a round.
     * @param _roundId The ID of the round
     */
    function getRoundMetadata(uint256 _roundId) external view returns (
        uint256 id,
        uint256 expectedSnapshotDatetime,
        uint256 maxFlareAmount,
        uint256 votingWindowEnd,
        uint256 abstainProposalId,
        uint256 latestId,
        uint256 snapshotBlock
    ) {
        if (_roundId == 0 || _roundId > roundId) {
            revert RoundIdOutOfRange();
        }

        Round storage round = roundData[_roundId].round;
        
        id = round.id;
        expectedSnapshotDatetime = round.expectedSnapshotDatetime;
        maxFlareAmount = round.maxFlareAmount;
        votingWindowEnd = round.roundStartDatetime + round.roundRuntime;
        abstainProposalId = round.abstainProposalId;
        latestId = roundId;
        snapshotBlock = round.snapshotBlock;
    }

    /**
     * Function to get the latest round
     */
    function getLatestRound() internal view returns (Round storage) {
        return roundData[roundId].round;
    }

    /**
     * Function to get all rounds
     */
    function getAllRounds() external view returns (Round[] memory) {
        Round[] memory allRounds = new Round[](roundId);
        for (uint256 i = 1; i <= roundId; i++) {
            Round storage round = roundData[i].round;
            allRounds[i-1] = round;
        }
        return allRounds;
    }

    /**
     * Function to kill a round
     * @param _roundId The ID of the round
     */
    function killRound(uint256 _roundId) external roundManagerOrAdmin {
        RoundData storage roundData_ = roundData[_roundId];
        Round storage round = roundData_.round;
        RoundStatus status = getRoundStatus(_roundId);
        
        // Can't kill rounds that are already claimed or expired
        if (status == RoundStatus.Claimed || status == RoundStatus.Expired) {
            revert RoundIsClosed();
        }

        round.status = RoundStatus.Expired;

        //Send funds back to grant fund wallet.
        (bool success, ) = floth.getGrantFundWallet().call{value: round.maxFlareAmount}("");
        require(success);

        emit RoundKilled(_roundId);
        emit RoundStatusUpdated(_roundId, RoundStatus.Expired);
    }

    /**
     * Retrieve proposal ID's and the number of votes for each, using pagination
     * @param _roundId The ID of the round
     * @param _pageNumber The page number
     * @param _pageSize The page size
     */
    function voteRetrieval(
        uint256 _roundId,
        uint256 _pageNumber,
        uint256 _pageSize
    ) external view returns (Votes[] memory) {
        if(_pageNumber == 0){
            revert InvalidPageNumberPageSize();
        }

        uint256 startIndex = (_pageNumber - 1) * _pageSize;
        uint256 endIndex = startIndex + _pageSize;

        if(_pageSize == 0){
            revert InvalidPageNumberPageSize();
        }

        RoundData storage roundData_ = roundData[_roundId];
        Round storage round = roundData_.round;
        
        if(round.proposalIds.length <= (endIndex-1)){
            endIndex = round.proposalIds.length;
        }

        uint256 resultSize = endIndex - startIndex;
        Votes[] memory voteRetrievals = new Votes[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            Proposal storage proposal = proposals[
                round.proposalIds[startIndex + i]
            ];
            voteRetrievals[i] = Votes({
                proposalId: proposal.id,
                voteCount: proposal.votesReceived
            });
        }
        return voteRetrievals;
    }

    /**
     * Get remaining voting power for a wallet
     * @param _address the address to get voting power
     */
    function getRemainingVotingPower(
        address _address
    ) external view returns (uint256) {
        RoundData storage currentRoundData = roundData[roundId];
        return currentRoundData.userRoundData[_address].votingPower;
    }

    /**
     * Get total voting power for holding Floth and FlothPass.
     * @param _address the address to get voting power
     */
    function getTotalVotingPower(address _address) public view returns (uint256) {
        Round memory latestRound = getLatestRound();

        if(latestRound.snapshotBlock == 0){
            return 0;
        }
        uint256 snapshotBlock = latestRound.snapshotBlock;

        //Get voting power for holding Floth.
        uint256 flothVotingPower = floth.getPastVotes(_address, snapshotBlock);

        //Get voting power for holding FlothPass.
        //TODO getTotalVotingPower uses flothPassesOwned from the snapshot but getFlothPassVotingPower uses the current number of FlothPasses owned.
        uint256 nftVotingPower = roundData[roundId].userRoundData[_address].flothPassesOwned * nftMultiplier;

        return flothVotingPower + nftVotingPower;
    }

    /**
     * Get voting power for holding Floth token.
     * @param _address the address to get voting power
     */
    function getFlothVotingPower(address _address) public view returns (uint256) {
        Round memory latestRound = getLatestRound();

        if(latestRound.snapshotBlock == 0){
            return 0;
        }
        uint256 snapshotBlock = latestRound.snapshotBlock;

        return floth.getPastVotes(_address, snapshotBlock);
    }

    /**
     * Get voting power for holding FlothPass token.
     * @param _address the address to get voting power
     */
    function getFlothPassVotingPower(address _address) public view returns (uint256) {
        Round storage round = getLatestRound();
        if(round.snapshotBlock == 0) {
            return 0;
        }
        // Use the built-in votes functionality
        //TODO shouldn't we use the flothPassesOwned from the snapshot?
        uint256 votingPower = flothPass.getPastVotes(_address, round.snapshotBlock);
        return votingPower * nftMultiplier;
    }

    /**
     * Check if the voting period is open
     */
    function isVotingPeriodOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        return getRoundStatus(latestRound.id) == RoundStatus.VotingOpen;
    }
    

    /**
     * Check if the submission window is open
     */
    function isSubmissionWindowOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        return getRoundStatus(latestRound.id) == RoundStatus.SubmissionOpen;
    }
    
    /**
     * Function to finish a round
     */
    function roundFinished() external roundManagerOrAdmin {
        RoundData storage currentRoundData = roundData[roundId];
        Round storage latestRound = currentRoundData.round;
        RoundStatus status = getRoundStatus(latestRound.id);

        if (status != RoundStatus.VotingOpen) {
            revert RoundIsOpen();
        }

        //Check which proposal has the most votes.
        Proposal memory mostVotedProposal = proposals[latestRound.proposalIds[0]];
        for (uint256 i = 0; i < latestRound.proposalIds.length; i++) {
            Proposal memory proposal = proposals[latestRound.proposalIds[i]];
            if (proposal.votesReceived > mostVotedProposal.votesReceived) {
                mostVotedProposal = proposal;
            }
        }

        //Add winning proposal to mappings.
        winningProposals[mostVotedProposal.receiver].push(mostVotedProposal);
        winningProposalByRoundId[latestRound.id] = mostVotedProposal;
        hasWinningProposal[mostVotedProposal.receiver] = true;

        //Check if the winning proposal is the abstain proposal.
        if (mostVotedProposal.id == latestRound.abstainProposalId) {
            mostVotedProposal.state = ProposalState.Abstained;
            winningProposalByRoundId[mostVotedProposal.roundId].state = ProposalState.Abstained;
            proposals[mostVotedProposal.id].state = ProposalState.Abstained;
            latestRound.status = RoundStatus.Expired;

            //Send funds back to grant fund wallet.
            (bool success, ) = floth.getGrantFundWallet().call{value: latestRound.maxFlareAmount}("");
            require(success);
            
            emit RoundStatusUpdated(latestRound.id, RoundStatus.Expired);
        } else {
            latestRound.status = RoundStatus.Completed;
            mostVotedProposal.state = ProposalState.Winning;
            winningProposalByRoundId[latestRound.id].state = ProposalState.Winning;
            proposals[mostVotedProposal.id].state = ProposalState.Winning;
            
            emit RoundStatusUpdated(latestRound.id, RoundStatus.Completed);
        }

        emit RoundCompleted(latestRound.id, mostVotedProposal.id);
    }

    /**
     * @dev Currently if a user has a winning proposal in multiple 
     * rounds they have to claim one at once.
     * Function to claim funds for a winning proposal
     */
    function claimFunds(uint256 _roundId) external nonReentrant {
        RoundData storage roundData_ = roundData[_roundId];
        RoundStatus status = getRoundStatus(_roundId);
        
        if (status != RoundStatus.Completed) {
            if (status == RoundStatus.Expired) {
                revert FundsClaimingPeriodExpired();
            } else if (status == RoundStatus.Claimed) {
                revert FundsAlreadyClaimed();
            } else {
                revert InvalidPermissions();
            }
        }

        if (!hasWinningProposal[msg.sender]) {
            revert InvalidClaimer();
        }

        Proposal[] storage usersWinningProposals = winningProposals[msg.sender];

        for (uint256 i = 0; i < usersWinningProposals.length; i++) {
            if(usersWinningProposals[i].state == ProposalState.Winning && 
               usersWinningProposals[i].roundId == _roundId) {
                Round storage claimRound = roundData_.round;

                //Check if 30 days have passed since round finished. 86400 seconds in a day.
                uint256 daysPassed = (block.timestamp - claimRound.roundStartDatetime + claimRound.roundRuntime) / 86400;

                //Check if 30 days have passed since round finished.
                if (daysPassed > 30) {
                    emit FundsNotClaimed(usersWinningProposals[i].id, msg.sender);
                    revert FundsClaimingPeriodExpired();
                }

                uint256 amountRequested = usersWinningProposals[i].amountRequested;
                if (address(this).balance < amountRequested) {
                    revert InsufficientBalance();
                }

                uint256 amountToSend = usersWinningProposals[i].amountRequested;
                address payable receiver = payable(usersWinningProposals[i].receiver);
                uint256 proposalId = usersWinningProposals[i].id;

                // Update all state before external call
                usersWinningProposals[i].state = ProposalState.Claimed;
                winningProposalByRoundId[usersWinningProposals[i].roundId].state = ProposalState.Claimed;
                proposals[proposalId].state = ProposalState.Claimed;
                roundData[_roundId].round.status = RoundStatus.Claimed;

                emit RoundStatusUpdated(_roundId, RoundStatus.Claimed);
                emit FundsClaimed(proposalId, msg.sender, amountToSend);

                // External call last (CEI pattern)
                (bool success, ) = receiver.call{value: amountToSend}("");
                if (!success) {
                    revert TransferFailed();
                }
                return;
            }
        }

        // Update round status through proposal state
        roundData_.round.status = RoundStatus.Claimed;
        emit RoundStatusUpdated(_roundId, RoundStatus.Claimed);
    }

    /**
     * Function to manually check if winning proposal hasn't been claimed.
     */
    function reclaimFunds(uint256 _roundId) external roundManagerOrAdmin {
        RoundData storage roundData_ = roundData[_roundId];
        Round storage round = roundData_.round;
        Proposal storage proposal = winningProposalByRoundId[_roundId];
        RoundStatus status = getRoundStatus(_roundId);

        if(status != RoundStatus.Completed) {
            if(status == RoundStatus.Expired) {
                revert FundsClaimingPeriodExpired();
            } else if(status == RoundStatus.Claimed) {
                revert FundsAlreadyClaimed();
            } else {
                revert InvalidPermissions();
            }
        }

        uint256 daysPassed = (block.timestamp - round.roundStartDatetime + round.roundRuntime) / 86400;

        if (daysPassed > 30) {
            // Update state to expired in all mappings
            proposal.state = ProposalState.Expired;
            round.status = RoundStatus.Expired;

            Proposal[] storage userProposals = winningProposals[proposal.receiver];
            for (uint256 i = 0; i < userProposals.length; i++) {
                if (userProposals[i].id == proposal.id) {
                    userProposals[i].state = ProposalState.Expired;
                    proposals[userProposals[i].id].state = ProposalState.Expired;
                }
            }
            
            // Send amount to the grant wallet
            (bool success, ) = floth.getGrantFundWallet().call{value: proposal.amountRequested}("");
            require(success);

            emit RoundStatusUpdated(_roundId, RoundStatus.Expired);
            emit FundsReclaimed(proposalId, floth.getGrantFundWallet(), proposal.amountRequested);
        }
    }

    /**
     * Function to get all winning proposals by roundID that have 
     * passed the claiming period and haven't been claimed.
     */
    function getUnclaimedWinningRoundIds() view external roundManagerOrAdmin returns (uint256[] memory) {
        // Get the count of unclaimed proposals
        uint256 count = 0;
        for (uint256 i = 1; i <= roundId; i++) {
            Proposal storage proposal = winningProposalByRoundId[i];
            Round memory round = roundData[i].round;

            if (proposal.state == ProposalState.Winning) { // Check if funds haven't been claimed
                uint256 daysPassed = (block.timestamp - round.roundStartDatetime + round.roundRuntime) / 86400;
                if (daysPassed > 30) {
                    count++;
                }
            }
        }

        // Initialize the memory array with the correct count
        uint256[] memory unclaimedWinningRoundIds = new uint256[](count);
        uint256 index = 0; // Index for the memory array

        // Populate the memory array with unclaimed round IDs
        for (uint256 i = 1; i <= roundId; i++) {
            Proposal storage proposal = winningProposalByRoundId[i];
            Round memory round = roundData[i].round;

            if (proposal.state == ProposalState.Winning) { // Check if funds haven't been claimed
                uint256 daysPassed = (block.timestamp - round.roundStartDatetime + round.roundRuntime) / 86400;
                if (daysPassed > 30) {
                    unclaimedWinningRoundIds[index] = i;
                    index++; // Move to the next position.
                }
            }
        }

        return unclaimedWinningRoundIds;
    }

    /**
     * Function to get the address of the Floth contract
     */
    function getFlothAddress() external view returns (address) {
        return address(floth);
    }

    // Replace multiple round state checks with a single function
    function getRoundStatus(uint256 _roundId) public view returns (RoundStatus) {
        Round storage round = roundData[_roundId].round;
        
        if (block.timestamp < round.roundStartDatetime) {
            return RoundStatus.NotStarted;
        }
        
        if (block.timestamp < round.expectedSnapshotDatetime) {
            return RoundStatus.SubmissionOpen;
        }
        
        if (block.timestamp <= round.roundStartDatetime + round.roundRuntime) {
            return RoundStatus.VotingOpen;
        }
        
        uint256 daysPassed = (block.timestamp - (round.roundStartDatetime + round.roundRuntime)) / 86400;
        if (daysPassed > 30) {
            return RoundStatus.Expired;
        }
        
        // Check if winning proposal exists and has been claimed
        Proposal storage winningProposal = winningProposalByRoundId[round.id];
        if (winningProposal.state == ProposalState.Claimed) {
            return RoundStatus.Claimed;
        }
        
        return RoundStatus.Completed;
    }
}
