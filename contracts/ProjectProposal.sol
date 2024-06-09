// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IFloth.sol";

contract ProjectProposal is AccessControl {
    // /**
    //  * TODO
    //  * */
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
        uint256 abstainProposalId;
        uint256 maxFlareAmount;
        uint256 roundStarttime;
        uint256 roundRuntime;
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256 votingRuntime;
        uint256 votingStartDate;
        uint256 votingEndDate;
        uint256[] proposalIds;
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

    mapping(address => mapping(uint256 => uint256)) public proposalsPerWallet; // (address => (roundId => count))
    mapping(address => mapping(uint256 => bool)) public hasVotedByRound; // (address => (roundId => voted))
    mapping(address => mapping(uint256 => uint256)) public votingPowerByRound; // (address => (roundId => power))

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

    error InvalidPermissions();
    error SubmissionWindowClosed();
    error VotingPeriodOpen();
    error InvalidAmountRequested();
    error InvalidVotingPower();
    error InvalidFlothAmount();
    error InsufficientBalance();
    error InsufficientFundsForRound();
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
    error InvalidAbstainVote();

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
        proposalsPerWallet[msg.sender][latestRound.id]++; //Increase proposal count for a wallet by 1.
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

    //Get proposals by user for a specific round.
    function getProposalsByAddress(
        uint256 _roundId,
        address _account
    ) external view returns (Proposal[] memory) {
        uint256 count = proposalsPerWallet[_account][_roundId];
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

    //Get a single proposal by ID.
    function getProposalById(
        uint256 _id
    ) public view returns (Proposal memory) {
        require(_id <= proposalId, "ProposalIdOutOfRange");
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

        Proposal storage proposal = proposals[_proposalId];
        Round storage currentRound = getLatestRound();
        uint256 currentVotingPower = votingPowerByRound[msg.sender][
            currentRound.id
        ];
        bool hasVoted = hasVotedByRound[msg.sender][currentRound.id];
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

        //If voting for the Abstain proposal.
        if (_proposalId == currentRound.abstainProposalId) {
            //Abstain vote can only be given to one proposal.
            if (hasVoted) {
                revert InvalidAbstainVote();
            } else {
                proposal.votesReceived += currentVotingPower; //Total voting power is voted.
                votingPowerByRound[msg.sender][currentRound.id] = 0; //All voting power is removed.
                hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.
            }
        }
        //Otherwise vote is for non-abstain proposal.
        else {
            proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.
            votingPowerByRound[msg.sender][currentRound.id] -= _numberOfVotes; //Reduce voting power in a round.
            hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.
        }

        emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
    }

    //Votes for a proposal within a round.
    function removeVotesFromProposal(uint256 _proposalId) external {
        Round storage currentRound = getLatestRound();
        //Check if the user hasn't voted yet.
        if (hasVotedByRound[msg.sender][currentRound.id]) {
            revert UserVoteNotFound();
        }
        uint256 currentVotingPower = votingPowerByRound[msg.sender][
            currentRound.id
        ];
        uint256 votesGiven = getVotingPower(msg.sender) - currentVotingPower; //Calculate votes given.
        Proposal storage proposal = proposals[_proposalId];
        proposal.votesReceived -= votesGiven; //Remove votes given to proposal.
        votingPowerByRound[msg.sender][currentRound.id] += votesGiven; //Give voting power back to user.
        hasVotedByRound[msg.sender][currentRound.id] = false; //Remove users has voted status.
        emit VotesRemoved(_proposalId, msg.sender, votesGiven);
    }

    //Add a new round (round).
    function addRound(
        uint256 _flrAmount,
        uint256 _roundRuntime,
        uint256 _snapshotDatetime,
        uint256 _votingRuntime
    ) external payable roundManagerOrAdmin {
        if (msg.value < _flrAmount) {
            revert InsufficientFundsForRound();
        }

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

        //Add 'Abstain' proposal for the new round.
        proposalId++;
        Proposal storage abstainProposal = proposals[proposalId];
        abstainProposal.id = proposalId;
        abstainProposal.roundId = roundId;
        abstainProposal.title = "Abstain";
        abstainProposal.amountRequested = 0;
        abstainProposal.receiver = address(0);
        abstainProposal.proposer = msg.sender;
        abstainProposal.fundsClaimed = false;

        newRound.proposalIds.push(proposalId); //Add abstain proposal to round struct.
        newRound.abstainProposalId = proposalId; //Used to track the abstain proposal of the round.

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
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < rounds[_roundId].proposalIds.length; i++) {
            totalVotes += proposals[rounds[_roundId].proposalIds[i]]
                .votesReceived;
        }
        return totalVotes;
    }

    //Get a single round by ID.
    //TODO: Do we need to give any round data to the UI? This is internal due to the mappings now
    function getRoundById(uint256 _id) public view returns (Round memory) {
        require(_id <= roundId, "RoundIdOutOfRange");
        return rounds[_id];
    }

    //Get the latest round.
    //TODO: Do we need to give any round data to the UI? This is internal due to the mappings now
    function getLatestRound() internal view returns (Round storage) {
        return rounds[roundId];
    }

    //Get all round.
    //TODO: Need to rework this as an array containing a nested mapping cannot be constructed in memory
    // function getAllRounds() internal view returns (Round[] storage) {
    //     uint256 count = roundIds.length;
    //     Round[] storage allRounds = new Round[](count);
    //     for (uint256 i = 0; i < count; i++) {
    //         Round storage round = rounds[roundIds[i]];
    //         allRounds[i] = round;
    //     }
    //     return allRounds;
    // }

    //Remove a round.
    function killRound(uint256 _roundId) external roundManagerOrAdmin {
        uint256 maxFlareAmount = rounds[_roundId].maxFlareAmount;
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

        //Send funds back to grant pool.
        (bool success, ) = msg.sender.call{value: maxFlareAmount}("");
        require(success);

        emit RoundKilled(_roundId);
    }

    //Retrieve proposal ID's and the number of votes for each, using pagination.
    function voteRetrieval(
        uint256 _roundId,
        uint256 _pageNumber,
        uint256 _pageSize
    ) external view returns (VoteRetrieval[] memory) {
        uint256 startIndex = (_pageNumber - 1) * _pageSize;
        uint256 endIndex = startIndex + _pageSize;
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

    //Get the remaining voting power for a user for a round.
    function getRemainingVotingPower(
        address _address
    ) external view returns (uint256) {
        return votingPowerByRound[_address][roundId];
    }

    //Get voting power for a user.
    function getVotingPower(address _address) public view returns (uint256) {
        uint256 snapshotBlock = getLatestRound().snapshotBlock;
        return floth.getPastVotes(_address, snapshotBlock);
    }

    //Check if we are in a voting period. This contract and the UI will call.
    function isVotingPeriodOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        return
            block.timestamp >= latestRound.votingStartDate &&
            block.timestamp <= latestRound.votingEndDate;
    }

    function isSubmissionWindowOpen() public view returns (bool) {
        Round storage latestRound = rounds[roundId];
        return
            block.timestamp < latestRound.snapshotDatetime &&
            block.timestamp > latestRound.roundStarttime;
    }

    //When a round is finished, allow winner to claim.
    function roundFinished() external roundManagerOrAdmin {
        Round storage latestRound = getLatestRound();

        if (latestRound.proposalIds.length == 0) {
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
        Round storage claimRound = rounds[winningProposal.roundId];
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

        if (winningProposal.receiver != msg.sender) {
            revert ClaimerNotRecipient();
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

    // Function to return the address of the floth contract
    function getFlothAddress() external view returns (address) {
        return address(floth);
    }
}
