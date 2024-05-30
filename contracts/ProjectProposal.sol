// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IFloth.sol";

contract ProjectProposal is AccessControl {
    /**
     * TODO
     * */

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");
    bytes32 public constant ROUND_MANAGER_ROLE =
        keccak256("ROUND_MANAGER_ROLE");

    IFloth internal floth;

    constructor(address _flothAddress) {
        if (_flothAddress == address(0)) {
            revert ZeroAddress();
        }
        floth = IFloth(_flothAddress);

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(SNAPSHOTTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ROUND_MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

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

    struct Round {
        uint256 id;
        uint256 maxFlareAmount;
        uint256 roundStarttime;
        uint256 roundRuntime;
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256 votingRuntime;
        uint256 votingStartDate;
        uint256 votingEndDate;
        Proposal[] proposals;
        mapping(address => uint256) proposalsPerWallet; //Tracks the number of proposals submitted by a wallet.
        mapping(address => bool) hasVoted; //Tracks if a wallet has voted in a round.
        mapping(address => uint256) currentVotingPower; //Tracks the current voting power per wallet.
    }

    //Used to return proposal id's and their vote count for a specific round.
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
    mapping(uint256 => Proposal) winningProposalsById;

    //Maps IDs to a round.
    mapping(uint256 => Round) rounds;

    //Keeps track of all round IDs.
    uint256[] roundIds;

    //Notify of a new proposal being added.
    event ProposalAdded(
        address creator,
        uint256 proposalId,
        string title,
        uint256 amountRequested
    );

    //Notify community when propsal receiver address is updated.
    event ProposalUpdated(uint256 proposalId, address newAddress);

    //Notify of a proposal being killed.
    event ProposalKilled(uint256 proposalId);

    //Notify of a new round being added.
    event RoundAdded(uint256 roundId, uint256 flrAmount, uint256 roundRuntime);

    //Notify about round completed and the winning proposal ID.
    event RoundCompleted(uint256 roundId, uint256 proposalId);

    //Notify of a round being killed.
    event RoundKilled(uint256 roundId);

    //Notify of votes added to a proposal.
    event VotesAdded(uint256 proposalId, address wallet, uint256 numberofVotes);

    //Notify of votes removed from a proposal.
    event VotesRemoved(
        uint256 proposalId,
        address wallet,
        uint256 numberofVotes
    );

    //Notify when snapshots are taken.
    event SnapshotTaken(uint256 roundId, uint256 snapshotBlock);

    //Notify when the winner has claimed the funds.
    event FundsClaimed(
        uint256 proposalId,
        address winningAddress,
        uint256 amountRequested
    );

    //Notify when roles are granted.
    event RoleGranted(bytes32 role, address grantedTo, address grantedBy);

    //Notify when roles are revoked.
    event RoleRevoked(bytes32 role, address revokedFrom, address revoker);

    error InvalidPermissions();
    error SubmissionWindowClosed();
    error VotingPeriodOpen();
    error AmountRequestedTooHigh();
    error InvalidVotingPower();
    error InvalidFlothAmount();
    error InsufficientBalance();
    error FundsAlreadyClaimed();
    error FundsClaimingPeriod();
    error InvalidClaimer();
    error ClaimerNotRecipient();
    error NoProposalsInRound();
    error RoundIsOpen();
    error RoundIsClosed();
    error InvalidSnapshotTime();
    error UserVoteNotFound();
    error ZeroAddress();
    error ProposalIdOutOfRange();

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

    //Add a new proposal using the users input - doesn't require to be owner.
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

        if (latestRound.maxFlareAmount < _amountRequested) {
            revert AmountRequestedTooHigh();
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

        rounds[latestRound.id].proposals.push(newProposal);
        rounds[latestRound.id].proposalsPerWallet[msg.sender] += 1; //Increase proposal count for a wallet by 1.

        emit ProposalAdded(msg.sender, proposalId, _title, _amountRequested);
    }

    //Allow user to update the proposal receiver address.
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
        emit ProposalUpdated(_proposalId, _newAddress);
    }

    //Get a single proposal by ID.
    function getProposalById(
        uint256 _id
    ) public view returns (Proposal memory) {
        if (_id > proposalId) {
            revert ProposalIdOutOfRange();
        }
        return proposals[_id];
    }

    //Votes for a proposal within a round.
    function addVotesToProposal(
        uint256 _proposalId,
        uint256 _numberOfVotes
    ) external {
        //Check if the user has FLOTH.
        if (floth.balanceOf(msg.sender) == 0) {
            revert InvalidFlothAmount();
        }

        Round storage currentRound = getLatestRound();
        uint256 currentVotingPower = currentRound.currentVotingPower[
            msg.sender
        ];
        bool hasVoted = currentRound.hasVoted[msg.sender];

        //Check if the users doesn't have a voting power set and they haven't already voted in the round.
        if (currentVotingPower == 0 && hasVoted) {
            revert InvalidVotingPower();
        } else if (currentVotingPower == 0 && !hasVoted) {
            currentVotingPower = floth.getPastVotes(
                msg.sender,
                currentRound.snapshotBlock
            );
        }

        //If the user doesn't have enough voting power, stop them from voting.
        if (currentVotingPower < _numberOfVotes) {
            revert InvalidVotingPower();
        }

        Proposal storage proposal = getProposalById(_proposalId);
        proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.

        currentVotingPower -= _numberOfVotes; //Reduce voting power in a round.
        currentRound.hasVoted[msg.sender] = true; //Set that the user has voted in a round.

        emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
    }

    //CASE FOR VOTING ON MUltiPLE PROJECts
    //Votes for a proposal within a round.
    function removeVotesFromProposal(uint256 _proposalId) external {
        Round storage currentRound = getLatestRound();

        //Check if the user hasn't voted yet.
        if (!currentRound.hasVoted[msg.sender]) {
            revert UserVoteNotFound();
        }

        uint256 currentVotingPower = currentRound.currentVotingPower[
            msg.sender
        ];
        uint256 votesGiven = getVotingPower(msg.sender) - currentVotingPower; //Calculate votes given.

        Proposal storage proposal = getProposalById(_proposalId);
        proposal.votesReceived -= votesGiven; //Remove votes given to proposal.

        currentVotingPower += votesGiven; //Give voting power back to user.
        currentRound.hasVoted[msg.sender] = false; //Remove users has voted status.

        emit VotesRemoved(_proposalId, msg.sender, votesGiven);
    }

    //Add a new round (round).
    function addRound(
        uint256 _flrAmount,
        uint256 _roundRuntime,
        uint256 _snapshotDatetime,
        uint256 _votingRuntime
    ) external roundManagerOrAdmin {
        roundId++;

        Round storage newRound = rounds[roundId]; //Needed for mappings in structs to work.
        newRound.id = roundId;
        newRound.maxFlareAmount = _flrAmount;
        newRound.roundStarttime = block.timestamp;
        newRound.roundRuntime = _roundRuntime;
        newRound.snapshotDatetime = _snapshotDatetime;
        newRound.votingStartDate = 0;
        newRound.votingEndDate = 0;
        newRound.snapshotBlock = block.number; //?
        newRound.votingRuntime = _votingRuntime;
        //newRound.proposals = []; Gets initialized by default.

        //Add 'Abstain' proposal for the new round. Should they give all their voting power to it?🟠
        proposalId++;
        Proposal storage abstainProposal = proposals[proposalId];
        abstainProposal.id = proposalId;
        abstainProposal.roundId = roundId;
        abstainProposal.title = "Abstain";
        abstainProposal.amountRequested = 0;
        abstainProposal.receiver = 0x0000000000000000000000000000000000000000;
        abstainProposal.proposer = msg.sender;
        abstainProposal.fundsClaimed = false;

        newRound.proposals.push(abstainProposal); //Add abstain proposal to round struct.

        roundIds.push(roundId); //Keep track of the round ids.

        emit RoundAdded(roundId, _flrAmount, _roundRuntime);
    }

    //Allow admin or Round Manager to update the round max flare amount.
    function setRoundMaxFlare(
        uint256 _newRoundMaxFlare
    ) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        if (roundToUpdate.maxFlareAmount != _newRoundMaxFlare) {
            if (address(this).balance < _newRoundMaxFlare) {
                revert InsufficientBalance();
            }
            roundToUpdate.maxFlareAmount = _newRoundMaxFlare;
        }
    }

    //Allow Admin or Round Manager to update the round runtime.
    function setRoundRuntime(
        uint256 _newRoundRuntime
    ) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        roundToUpdate.roundRuntime = _newRoundRuntime;
    }

    //Allow Admin or Round Manager to update the round snapshot date time.
    function setRoundSnapshotDatetime(
        uint256 _newSnapshotDatetime
    ) external managerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        if (block.timestamp < _newSnapshotDatetime) {
            revert InvalidSnapshotTime();
        }

        roundToUpdate.snapshotDatetime = _newSnapshotDatetime;
    }

    //Take a snapshot for the current round.
    function takeSnapshot() external managerOrAdmin {
        Round storage round = getLatestRound();

        if (block.timestamp <= round.snapshotDatetime) {
            revert InvalidSnapshotTime();
        }
        if (block.timestamp > (round.roundStarttime + round.roundRuntime)) {
            revert RoundIsClosed();
        }

        round.snapshotBlock = block.number;

        // Set voting period start and end times
        round.votingStartDate = block.timestamp;
        round.votingEndDate = block.timestamp + round.votingRuntime;

        emit SnapshotTaken(round.id, round.snapshotBlock);
    }

    //Allow owner to update the round voting runtime.
    function setRoundVotingRuntime(
        uint256 _newVotingRuntime
    ) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        roundToUpdate.votingRuntime = _newVotingRuntime;
    }

    //Get the total votes for a specifc round.
    function getTotalVotesForRound(
        uint256 _roundId
    ) external view returns (uint256) {
        Proposal[] storage requestedProposals = getRoundById(_roundId)
            .proposals;
        uint256 totalVotes = 0;

        //Iterate through proposals and count all votes.
        for (uint256 i = 0; i < requestedProposals.length; i++) {
            totalVotes += requestedProposals[i].votesReceived;
        }

        return totalVotes;
    }

    //Get a single round by ID.
    function getRoundById(uint256 _id) public view returns (Round memory) {
        return rounds[_id];
    }

    //Get the latest round.
    function getLatestRound() public view returns (Round memory) {
        return rounds[roundId];
    }

    //Get all round.
    function getAllRounds() external view returns (Round[] memory) {
        uint256 count = roundIds.length;
        Round[] memory allRounds = new Round[](count);
        for (uint256 i = 0; i < count; i++) {
            Round storage round = rounds[roundIds[i]];
            allRounds[i] = round;
        }
        return allRounds;
    }

    //Remove a round.
    function killRound(uint256 _roundId) external roundManagerOrAdmin {
        //remove round from mapping.
        delete rounds[_roundId];

        //remove round id from array.
        for (uint256 i = 0; i < roundIds.length; i++) {
            if (roundIds[i] == _roundId) {
                roundIds[i] = roundIds[roundIds.length - 1];
                roundIds.pop();
                break;
            }
        }
        emit RoundKilled(_roundId, "Round killed successfully.");
    }

    //Retrieve proposal ID's and the number of votes for each, using pagination.
    function voteRetrieval(
        uint256 _roundId,
        uint256 _pageNumber,
        uint256 _pageSize
    ) external view returns (VoteRetrieval[] memory) {
        Proposal[] memory requestedProposals = getRoundById(_roundId).proposals;

        //Start/end indexes of proposals to return.
        uint256 startIndex = (_pageNumber - 1) * _pageSize;
        uint256 endIndex = startIndex + _pageSize;

        //Check end index is not bigger than proposal length.
        if (endIndex > requestedProposals.length) {
            endIndex = requestedProposals.length;
        }

        uint256 resultSize = endIndex - startIndex; //Should equal _pageSize, but may not if final page.

        VoteRetrieval[] memory voteRetrievals = new VoteRetrieval[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            voteRetrievals[i] = VoteRetrieval({
                proposalId: requestedProposals[startIndex + i].id,
                voteCount: requestedProposals[startIndex + i].votesReceived
            });
        }

        return voteRetrievals;
    }

    //Get the remaining voting power for a user for a round.
    function getRemainingVotingPower(
        address _address
    ) external view returns (uint256) {
        return getLatestRound().currentVotingPower[_address];
    }

    //Get voting power for a user.
    function getVotingPower(address _address) external view returns (uint256) {
        uint256 snapshotBlock = getLatestRound().snapshotBlock;

        uint256 votingPower = floth.getPastVotes(_address, snapshotBlock);

        return votingPower;
    }

    //Check if we are in a voting period. This contract and the UI will call.
    function isVotingPeriodOpen() public view returns (bool) {
        bool inVotingPeriod = false;

        Round memory latestRound = getLatestRound();

        if (
            block.timestamp >= latestRound.votingStartDate &&
            block.timestamp <= latestRound.votingEndDate
        ) {
            inVotingPeriod = true;
        }

        return inVotingPeriod;
    }

    function isSubmissionWindowOpen() public view returns (bool) {
        Round memory latestRound = rounds[roundId];
        return (block.timestamp < latestRound.snapshotDatetime &&
            block.timestamp > latestRound.roundStarttime);
    }

    //When a round is finished, allow winner to claim.
    function roundFinished() external roundManagerOrAdmin {
        Round memory latestRound = getLatestRound();
        Proposal[] memory latestProposals = latestRound.proposals;

        if (latestProposals.length == 0) {
            revert NoProposalsInRound();
        }

        //Check if round is over.
        if (
            (latestRound.roundStarttime + latestRound.roundRuntime) <
            block.timestamp
        ) {
            revert RoundIsOpen();
        }

        //Check which proposal has the most votes.
        Proposal memory mostVotedProposal = latestProposals[0];
        for (uint256 i = 0; i < latestProposals.length; i++) {
            if (
                latestProposals[i].votesReceived >
                mostVotedProposal.votesReceived
            ) {
                mostVotedProposal = latestProposals[i];
            }
        }

        //Add winning proposal to mappings.
        winningProposals[mostVotedProposal.receiver] = mostVotedProposal;
        winningProposalsById[latestRound.id] = mostVotedProposal;
        hasWinningProposal[mostVotedProposal.receiver] = true;

        emit RoundCompleted(latestRound.id, mostVotedProposal.id);
    }

    //When a round is finished, allow winner to claim.
    function claimFunds() external {
        //Check if the wallet has won a round.
        if (!hasWinningProposal[msg.sender]) {
            revert InvalidClaimer();
        }

        Proposal storage winningProposal = winningProposals[msg.sender];

        //Check if 30 days have passed since round finished. 86400 seconds in a day.
        Round memory claimRound = getRoundById(winningProposal.roundId);
        uint256 daysPassed = (block.timestamp -
            claimRound.roundStarttime +
            claimRound.roundRuntime) / 86400;
        if (daysPassed > 30) {
            revert FundsClaimingPeriod();
        }

        //Check if the funds have already been claimed.
        if (winningProposal.fundsClaimed) {
            revert FundsAlreadyClaimed();
        }

        address recipient = winningProposal.receiver;
        if (recipient != msg.sender) {
            revert ClaimerNotRecipient();
        }

        uint256 amountRequested = winningProposal.amountRequested;
        if (address(this).balance < amountRequested) {
            revert InsufficientBalance();
        }

        winningProposal.fundsClaimed = true; //Set as claimed so winner cannot reclaim for the proposal.

        //Send amount requested to winner.
        (bool success, ) = recipient.call{value: amountRequested}("");
        require(success);

        emit FundsClaimed(winningProposal.id, msg.sender, amountRequested);
    }
}
