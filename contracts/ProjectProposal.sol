// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IFloth.sol";

/**
 * @title ProjectProposal contract for the Floth protocol
 * @author Ethereal Labs
 */
contract ProjectProposal is AccessControl {
    // Define roles for the contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");
    bytes32 public constant ROUND_MANAGER_ROLE =
        keccak256("ROUND_MANAGER_ROLE");

    // Define the Floth interface
    IFloth internal floth;

    /**
     * Constructor for the ProjectProposal contract
     * @param _flothAddress The address of the Floth contract
     */
    constructor(address _flothAddress) {
        if (_flothAddress == address(0)) {
            revert ZeroAddress();
        }
        floth = IFloth(_flothAddress);

        _setRoleAdmin(SNAPSHOTTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ROUND_MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // TODO Change address when we deploy
        _grantRole(ADMIN_ROLE, msg.sender); // TODO Change address when we deploy
    }

    // Proposal struct to store proposal data
    struct Proposal {
        uint256 id;
        uint256 roundId; //Tracked for claiming funds.
        string title;
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer; //The wallet that submitted the proposal.
        address receiver; //The wallet that will receive the funds.
        bool fundsClaimed; //Tracked here incase funds are not claimed before new round begins.
    }

    // Round struct to store round data
    struct Round {
        uint256 id;
        uint256 abstainProposalId;
        uint256 maxFlareAmount;
        uint256 roundStartDatetime;
        uint256 roundRuntime;
        uint256 expectedSnapshotDatetime;
        uint256 snapshotBlock;
        uint256[] proposalIds;
        bool isActive;
    }

    //Used to return proposal ids and their vote count for a specific round.
    struct VoteRetrieval {
        uint256 proposalId;
        uint256 voteCount;
    }

    //Tracks ID number for each proposal.
    uint256 public proposalId = 0;

    //Tracks ID number for each round.
    uint256 public roundId = 0;

    //Maps IDs to a proposal.
    mapping(uint256 => Proposal) proposals;

    //Maps address to a bool for proposal winners.
    mapping(address => bool) hasWinningProposal;

    //Maps winning address to winning proposals.
    mapping(address => Proposal) winningProposals;

    //Maps winning roundID to winning proposals.
    mapping(uint256 => Proposal) winningProposalsByRoundId;

    //Maps IDs to a round.
    mapping(uint256 => Round) rounds;

    // Mappings of mappings //

    // Number of proposals per wallet for a specific round.
    mapping(address => mapping(uint256 => uint256))
        public proposalsPerWalletPerRound; // (address => (roundId => count))

    // Mapping to check if wallet has voted in particular round.
    mapping(address => mapping(uint256 => bool)) public hasVotedByRound; // (address => (roundId => voted))

    // Voting power for a wallet in a specific round.
    mapping(address => mapping(uint256 => uint256)) public votingPowerByRound; // (address => (roundId => power))

    // Tracks the proposals that an address has voted on.
    mapping(address => mapping(uint256 => uint256[])) public votedOnProposals; // (address => (roundId => proposals))

    //Keeps track of all round IDs.
    uint256[] roundIds;

    /**
     * Events for the ProjectProposal contract
     */
    event ProposalAdded(
        address creator,
        uint256 proposalId,
        uint256 roundId,
        string title,
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
    event SnapshotTaken(uint256 roundId, uint256 snapshotBlock);
    event FundsClaimed(
        uint256 proposalId,
        address winningAddress,
        uint256 amountRequested
    );
    event expectedSnapshotDatetimeUpdated(
        uint256 roundId,
        uint256 newexpectedSnapshotDatetime
    );
    event RoundRuntimeUpdated(uint256 roundId, uint256 newRoundRuntime);
    event RoundMaxFlareSet(uint256 newMaxFlare);

    /**
     * Error messages for the ProjectProposal contract
     */
    error InvalidPermissions();
    error SubmissionWindowClosed();
    error VotingPeriodOpen();
    error InvalidAmountRequested();
    error InvalidVotingPower();
    error InvalidFlothAmount();
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
    error InvalidAbstainVote();
    error InvalidRoundRuntime();

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
     * @param _title The title of the proposal
     * @param _amountRequested The amount requested for the proposal
     */
    function addProposal(
        string memory _title,
        uint256 _amountRequested
    ) external {
        Round storage latestRound = getLatestRound();

        //If submission window is closed, revert.
        if (!isSubmissionWindowOpen()) {
            revert SubmissionWindowClosed();
        }

        //If within a voting period, revert.
        if (isVotingPeriodOpen()) {
            revert VotingPeriodOpen();
        }

        if (
            latestRound.maxFlareAmount < _amountRequested ||
            _amountRequested == 0
        ) {
            revert InvalidAmountRequested();
        }

        proposalId++;
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.roundId = latestRound.id;
        newProposal.title = _title;
        newProposal.amountRequested = _amountRequested;
        newProposal.receiver = msg.sender; //receiver set to msg.sender by default.
        newProposal.proposer = msg.sender;
        newProposal.fundsClaimed = false;
        rounds[latestRound.id].proposalIds.push(proposalId); //Add proposal ID to round struct.
        proposalsPerWalletPerRound[msg.sender][latestRound.id]++; //Increase proposal count for a wallet by 1.
        emit ProposalAdded(
            msg.sender,
            proposalId,
            latestRound.id,
            _title,
            _amountRequested
        );
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

        //Prevent proposer updating receiver address during voting window.
        if (isVotingPeriodOpen()) {
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
        uint256 count = proposalsPerWalletPerRound[_account][_roundId];
        Proposal[] memory accountProposals = new Proposal[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < rounds[_roundId].proposalIds.length; i++) {
            Proposal storage proposal = proposals[
                rounds[_roundId].proposalIds[i]
            ];
            if (proposal.proposer == _account) {
                accountProposals[index] = proposal;
                index++;
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
        //Check if the user has voting power.
        if (getVotingPower(msg.sender) == 0) {
            revert InvalidFlothAmount();
        }

        Proposal storage proposal = proposals[_proposalId];
        Round storage currentRound = getLatestRound();

        bool hasVoted = hasVotedByRound[msg.sender][currentRound.id];
        uint256 currentVotingPower;

        //If they haven't voted yet, set votingPowerByRound, else retrieve current voting power.
        if(!hasVoted){
            currentVotingPower = getVotingPower(msg.sender);
            votingPowerByRound[msg.sender][currentRound.id] = currentVotingPower;
        }else{
         currentVotingPower = votingPowerByRound[msg.sender][currentRound.id];
        }

        //If voting for the Abstain proposal.
        if (_proposalId == currentRound.abstainProposalId) {
            //Abstain vote can only be given to one proposal.

            proposal.votesReceived += getVotingPower(msg.sender); //Voting power re-retrieved as may be reduced if previously voted.
            votingPowerByRound[msg.sender][currentRound.id] = 0; //All voting power is removed.
            hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.
            
            uint256[] memory previousVotedProposals = votedOnProposals[msg.sender][currentRound.id];
            //Remove votes on other proposals.
            if(previousVotedProposals.length > 0){
                for (uint256 i = 0; i < previousVotedProposals.length; i++) {
                    //TODO: how do we know how many votes a user gave to previous proposals? Track this in another mapping too?
                }
            }
        }

        //Check if the user doesn't have any voting power set, revert. Checked here to let users call abstain if no power left.
        if (currentVotingPower == 0) {
            revert InvalidVotingPower();
        } 
        
        //If the user doesn't have enough voting power, stop them from voting.
        if (currentVotingPower < _numberOfVotes) {
            revert InvalidVotingPower();
        }

        //Otherwise vote is for non-abstain proposal.
        else {            
            proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.
            votingPowerByRound[msg.sender][currentRound.id] -= _numberOfVotes; //Reduce voting power in a round.
            hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.
            votedOnProposals[msg.sender][currentRound.id].push(_proposalId); // Track proposals that a user has voted on (needed to abstain).
        }

        emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
    }

    /**
     * Function to remove votes from a proposal
     * @param _proposalId The ID of the proposal
     */
    function removeVotesFromProposal(uint256 _proposalId) external {
        Round storage currentRound = getLatestRound();

        //Check if the user hasn't voted.
        if (!hasVotedByRound[msg.sender][currentRound.id]) {
            revert UserVoteNotFound();
        }

        uint256 currentVotingPower = votingPowerByRound[msg.sender][
            currentRound.id
        ];

        //TODO: This is the total votes given, but we are just removing votes given to a particular proposal?
        uint256 votesGiven = getVotingPower(msg.sender) - currentVotingPower; //Calculate votes given.
        Proposal storage proposal = proposals[_proposalId];
        proposal.votesReceived -= votesGiven; //Remove votes given to proposal.
        votingPowerByRound[msg.sender][currentRound.id] += votesGiven; //Give voting power back to user.

        //TODO: May not need this voting flag.
        hasVotedByRound[msg.sender][currentRound.id] = false; //Remove users has voted status.
        emit VotesRemoved(_proposalId, msg.sender, votesGiven);
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
        Round storage newRound = rounds[roundId]; //Needed for mappings in structs to work.
        newRound.id = roundId;
        newRound.maxFlareAmount = _maxFlareAmount;
        newRound.roundStartDatetime = block.timestamp;
        newRound.roundRuntime = _roundRuntime;
        newRound.expectedSnapshotDatetime = _expectedSnapshotDatetime;
        newRound.snapshotBlock = block.number; //TODO: We can't set this here, but if we don't what happens?
        newRound.isActive = true;

        //Add 'Abstain' proposal for the new round.
        proposalId++;
        Proposal storage abstainProposal = proposals[proposalId];
        abstainProposal.id = proposalId;
        abstainProposal.roundId = roundId;
        abstainProposal.title = "Abstain";
        abstainProposal.amountRequested = 0;
        abstainProposal.receiver = msg.sender;
        abstainProposal.proposer = msg.sender;
        abstainProposal.fundsClaimed = false;

        newRound.proposalIds.push(proposalId); //Add abstain proposal to round struct.
        newRound.abstainProposalId = proposalId; //Used to track the abstain proposal of the round.

        roundIds.push(roundId); //Keep track of the round ids.
        emit RoundAdded(roundId, _maxFlareAmount, _roundRuntime);
    }

    /**
     * Function to increase the max flare amount for a round
     */
    function increaseRoundMaxFlare() external payable roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        if (msg.value == 0) {
            revert InvalidAmountRequested();
        }

        if (!isSubmissionWindowOpen()) {
            revert SubmissionWindowClosed();
        }

        roundToUpdate.maxFlareAmount += msg.value;
        emit RoundMaxFlareSet(roundToUpdate.maxFlareAmount);
    }

    /**
     * Function to extend the runtime of a round
     * @param _newRoundRuntime The new runtime for the round
     */
    function extendRoundRuntime(
        uint256 _newRoundRuntime
    ) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        // Ensure the new runtime is greater than the current round runtime
        if (_newRoundRuntime <= roundToUpdate.roundRuntime) {
            revert InvalidRoundRuntime();
        }

        // Check if round is closed
        if (
            block.timestamp >
            (roundToUpdate.roundStartDatetime + roundToUpdate.roundRuntime)
        ) {
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
    function extendRoundExpectedSnapshotDatetime(
        uint256 _newExpectedSnapshotDatetime
    ) external managerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

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
        emit expectedSnapshotDatetimeUpdated(
            roundId,
            _newExpectedSnapshotDatetime
        );
        emit RoundRuntimeUpdated(roundId, roundToUpdate.roundRuntime);
    }

    /**
     * Function to take a snapshot of the current block
     */
    function takeSnapshot() external managerOrAdmin {
        Round storage round = getLatestRound();

        if (block.timestamp < round.expectedSnapshotDatetime) {
            revert InvalidSnapshotTime();
        }

        if (block.timestamp > (round.roundStartDatetime + round.roundRuntime)) {
            revert RoundIsClosed();
        }

        //TODO: Set the snapshot datetime (but we need to think of consequences of this)
        // round.snapshotDateTime = block.timestamp;
        // need a way to check if the snapshot has been taken already
        round.snapshotBlock = block.number;

        emit SnapshotTaken(round.id, round.snapshotBlock);
    }

    /**
     * Function to get the total votes for a round
     */
    function getTotalVotesForRound(
        uint256 _roundId
    ) external view returns (uint256) {
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < rounds[_roundId].proposalIds.length; i++) {
            totalVotes += proposals[rounds[_roundId].proposalIds[i]]
                .votesReceived;
        }
        return totalVotes;
    }

    /**
     * Get a round given a particular id
     * @param _id The ID of the round
     */
    function getRoundById(uint256 _id) public view returns (Round memory) {
        if (_id > roundId) {
            revert ProposalIdOutOfRange();
        }
        return rounds[_id];
    }

    /**
     * Function to get the latest round
     */
    function getLatestRound() internal view returns (Round storage) {
        return rounds[roundId];
    }

    /**
     * Function to get all rounds
     */
    function getAllRounds() internal view returns (Round[] memory) {
        uint256 count = roundIds.length;
        Round[] memory allRounds = new Round[](count);
        for (uint256 i = 0; i < count; i++) {
            Round storage round = rounds[roundIds[i]];
            allRounds[i] = round;
        }
        return allRounds;
    }

    /**
     * Function to kill a round
     * @param _roundId The ID of the round
     */
    function killRound(uint256 _roundId) external roundManagerOrAdmin {
        uint256 maxFlareAmount = rounds[_roundId].maxFlareAmount;
        //set round as inactive.
        rounds[_roundId].isActive = false;

        //Send funds back to msg sender.
        //TODO: Send to grant fund wallet not msg.sender
        (bool success, ) = msg.sender.call{value: maxFlareAmount}("");
        require(success);

        emit RoundKilled(_roundId);
    }

    /**
     * Retrieve proposal ID's and the number of votes for each, using pagination
     * @param _roundId The ID of the round
     * @param _pageNumber The page number
     * @param _pageSize The page size
     */
    //TODO: Review with Jake
    function voteRetrieval(
        uint256 _roundId,
        uint256 _pageNumber,
        uint256 _pageSize
    ) external view returns (VoteRetrieval[] memory) {
        uint256 startIndex = (_pageNumber - 1) * _pageSize;
        uint256 endIndex = startIndex + _pageSize;

        //Add page number and page size 0 check.

        if (endIndex > rounds[_roundId].proposalIds.length) {
            endIndex = rounds[_roundId].proposalIds.length;
        }
        uint256 resultSize = endIndex - startIndex;
        VoteRetrieval[] memory voteRetrievals = new VoteRetrieval[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            Proposal storage proposal = proposals[
                rounds[_roundId].proposalIds[startIndex + i]
            ];
            voteRetrievals[i] = VoteRetrieval({
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
        // TODO: This is never set? Could this be calculated?
        return votingPowerByRound[_address][roundId];
    }

    /**
     * Get voting power for a wallet
     * @param _address the address to get voting power
     */
    function getVotingPower(address _address) public view returns (uint256) {
        uint256 snapshotBlock = getLatestRound().snapshotBlock;
        return floth.getPastVotes(_address, snapshotBlock);
    }

    /**
     * Check if the voting period is open
     */
    //TODO: We may want this to not go off the expected but of the snapshot time
    // we should record when taking a snapshot
    function isVotingPeriodOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        return
            block.timestamp >= latestRound.expectedSnapshotDatetime &&
            block.timestamp <=
            latestRound.roundStartDatetime + latestRound.roundRuntime;
    }

    /**
     * Check if the submission window is open
     */
    function isSubmissionWindowOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        return
            block.timestamp < latestRound.expectedSnapshotDatetime &&
            block.timestamp > latestRound.roundStartDatetime;
    }

    /**
     * Function to finish a round
     */
    function roundFinished() external roundManagerOrAdmin {
        Round storage latestRound = getLatestRound();

        //TODO: What happens to the funds in this case? We want to be able to get them out!
        if (latestRound.proposalIds.length == 0) {
            revert NoProposalsInRound();
        }

        //Check if round is over.
        if (
            (latestRound.roundStartDatetime + latestRound.roundRuntime) <
            block.timestamp
        ) {
            revert RoundIsOpen();
        }

        //Check which proposal has the most votes.
        Proposal memory mostVotedProposal = proposals[
            latestRound.proposalIds[0]
        ];
        for (uint256 i = 0; i < latestRound.proposalIds.length; i++) {
            Proposal memory proposal = proposals[latestRound.proposalIds[i]];
            if (proposal.votesReceived > mostVotedProposal.votesReceived) {
                mostVotedProposal = proposal;
            }
        }

        //Add winning proposal to mappings.
        winningProposals[mostVotedProposal.receiver] = mostVotedProposal;
        winningProposalsByRoundId[latestRound.id] = mostVotedProposal;
        hasWinningProposal[mostVotedProposal.receiver] = true;
        emit RoundCompleted(latestRound.id, mostVotedProposal.id);
    }

    /**
     * Function to claim funds for a winning proposal
     */
    //TODO: We need a way to get the funds out if they are not claimed
    // perhaps a new admin function that can be called 30 days after a winning proposal has expired?
    function claimFunds() external {
        //TODO: Need to probably add round ID, what happens if this wallet has multiple winning proposals?
        //Check if the wallet has won a round.
        if (!hasWinningProposal[msg.sender]) {
            revert InvalidClaimer();
        }

        Proposal storage winningProposal = winningProposals[msg.sender];

        //Check if 30 days have passed since round finished. 86400 seconds in a day.
        Round storage claimRound = rounds[winningProposal.roundId];

        uint256 daysPassed = (block.timestamp -
            claimRound.roundStartDatetime +
            claimRound.roundRuntime) / 86400;
        if (daysPassed > 30) {
            revert FundsClaimingPeriodExpired();
        }

        //Check if the funds have already been claimed.
        if (winningProposal.fundsClaimed) {
            revert FundsAlreadyClaimed();
        }

        uint256 amountRequested = winningProposal.amountRequested;
        if (address(this).balance < amountRequested) {
            revert InsufficientBalance();
        }

        winningProposal.fundsClaimed = true; //Set as claimed so winner cannot reclaim for the proposal.

        //Send amount requested to winner.
        (bool success, ) = winningProposal.receiver.call{
            value: amountRequested
        }("");
        require(success);

        emit FundsClaimed(winningProposal.id, msg.sender, amountRequested);
    }

    /**
     * Function to get the address of the Floth contract
     */
    function getFlothAddress() external view returns (address) {
        return address(floth);
    }
}
