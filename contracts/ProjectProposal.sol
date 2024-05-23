// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IFloth.sol";

contract ProjectProposal is Ownable {
    /**
     * What does the front end need/TODO
     *
     * - Create proposal function (name/amount requested/proposer and receiver set to msg.sender initially). ✅
     * - Change "round" to "round". ✅
     * - No description on chain. ✅
     * - Remove setter for amount requested. -✅ Kyle said to now keep.
     * - Event emitted when proposal is created (creator proposal address, proposal id (make it more like a uid using keccak or something, use 16 bytes).✅
     * - Can ONLY submit proposals during "submission window" during a round. Should be locked otherwise. Front end needs to read this lock. ✅
     * - View function to get proposals and their votes and paginated, index 0 gives first x, index 1 give second x amount etc.
     * - Add winners array and remove the "accepted" bool. ✅
     * - Add AccessControl for role permissoning to the contract. Roles: ADMIN, SNAPSHOTTER, ROUND_MANAGER
     */

    /**
    *
    * - Add an address to constructor argument that creates an IERC20Votes contract (Create interface which reduces the number of functions we need to pass) instead of making this it's own ERCVotes. ✅
    *
    * Do we need a history of round? This will determine if we need roundid tracings. - yes, may as well have this ✅
    *
    * When are we taking snapshots? doing it 2 weeks after round opens could be tricky - We do need a snapshot function that can be called when round is ready for voting on. ✅🟠🟠🟠
    *
    *use reverts instead of require, revert errors. ✅
    *
    *change to external contracts where necessary ✅

    * add receiver address to proposal ✅
    * Add complete round function which sends funds to receiver address. - highest votes ✅
    * kill proposal function. ✅
    * setter for current round - maxFlareAmount; roundRunTime;  snapshotDatetime; snapshotBlock; votingRuntime; -- onlyowner.  ✅
    */

    IFloth internal floth;

    constructor(address _flothAddress) {
        floth = IFloth(_flothAddress);
    }

    struct Proposal {
        uint256 id;
        string title;
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer; //The wallet that submitted the proposal.
        address receiver; //The wallet that will receive the funds.
        bool fundsClaimedIfWinner; //Tracked here incase funds are not claimed before new round begins.
    }

    struct Round {
        uint256 id;
        uint256 maxFlareAmount;
        uint256 roundStarttime;
        uint256 roundRuntime;
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256 votingRuntime;
        Proposal[] proposals;
        mapping(address => uint256) proposalsPerWallet; //Tracks the number of proposals submitted by a wallet.
        mapping(address => bool) hasVoted; //Tracks if a wallet has voted in a round.
        mapping(address => uint256) currentVotingPower; //Tracks the current voting power per wallet.
    }

    //Tracks ID number for each proposal.
    uint256 proposalId = 0;

    //Tracks ID number for each round.
    uint256 roundId = 0;

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
    event ProposalAdded(address creator, uint16 proposalId, string title, uint256 amountRequested);

    //Notify of a proposal being killed.
    event ProposalKilled(uint256 proposalId);

    //Notify of a new round being added.
    event RoundAdded(string name, uint256 amountRequested);

    //Notify of a round being killed.
    event RoundKilled(uint256 roundId);

    //Notify of votes added to a proposal.
    event VotesAdded(uint256 proposalId, address wallet, uint256 numberofVotes);

    //Add a new proposal using the users input - doesn't require to be owner.
    function addProposal(string memory _title,uint256 _amountRequested) external {
        Round memory latestRound = getLatestRound();

        if(latestRound.maxFlareAmount < _amountRequested){
            revert("Amount requested is more than the max amount for the round.");
        }
        
        //If within a voting period, revert.
        if(getVotingPeriod()){
            revert("Cannot submit proposal during voting period.");
        }

        proposalId++;

        Proposal memory newProposal = Proposal(
            proposalId,
            _title,
            _amountRequested,
            msg.sender,
            msg.sender, //receiver set to msg.sender by default.
            false
        );

        // proposals[msg.sender].push(newProposal); //Removed and moved to Round struct.
        proposals[proposalId] = newProposal;
        round[roundId].proposals.push(newProposal);
        round[roundId].proposalsPerWallet[msg.sender] += 1; //Increase proposal count for a wallet by 1.

        emit ProposalAdded(msg.sender, proposalId, _title, _amountRequested);
    }

    //Allow user to update the proposal receiver address.
    function setProposalReceiverAddress(uint256 _proposalId, address _newAddress) external {
        Proposal storage proposalToUpdate = proposals[_proposalId];

        //Only proposer can update receiver address.
        if (msg.sender != proposalToUpdate.proposer) {
            revert("You must be the proposer of the proposal to update.");
        }

        proposalToUpdate.receiver = _newAddress;
    }

    //Get a single proposal by ID.
    function getProposalById(uint256 _id) external view returns (Proposal) {
        return proposals[_id];
    }

    //Votes for a proposal within a round.
    function addVotesToProposal(uint256 _proposalId, uint256 _numberOfVotes) external {
        //Check if the user has FLOTH.
        if (floth.balanceOf(msg.sender) == 0) {
            revert("User doesn't have FLOTH.");
        } 

        Round storage currentRound = getLatestRound();
        uint256 currentVotingPower = currentRound.currentVotingPower[msg.sender];

        //Check if the users doesn't have a voting power set and they haven already voted in the round.
         if(currentVotingPower == 0 && currentRound.hasVoted[msg.sender]){
            revert("No voting power left in this round.");
         }
         else if(currentVotingPower == 0 && !currentRound.hasVoted[msg.sender]){
            currentVotingPower = floth.getPastVotes(msg.sender, currentRound.snapshotBlock);
        }

        //If the user doesn't have enough voting power, stop them from voting.
        if(currentVotingPower < _numberOfVotes){
           revert("Not enough voting power to vote that amount of votes.");
        }

        Proposal storage proposal = getProposalById(_proposalId);
        proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.

        currentVotingPower -= _numberOfVotes; //Reduce voting power in a round.
        currentRound.hasVoted[msg.sender] = true; //Set that the user has voted in a round.

        //update their voting power.
        emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
    }

    //Add a new round (round).
    function addRound(
        uint256 _flrAmount,
        uint256 _roundRuntime,
        uint256 _snapshotDatetime,
        uint256 _votingRuntime
    ) external onlyOwner {
        roundId++;

        Round storage newRound = round[roundId]; //Needed for mappings in structs to work.
        newRound.id = roundId;
        newRound.maxFlareAmount = _flrAmount;
        newRound.roundStarttime = block.timestamp;
        newRound.roundRuntime = _roundRuntime;
        newRound.snapshotDatetime = _snapshotDatetime;
        newRound.snapshotBlock = block.number; //?
        newRound.votingRuntime = _votingRuntime;
        newRound.proposals = [];

        roundIds.push(roundId); //Keep track of the round ids.

        emit RoundAdded(roundId, _flrAmount, _roundRuntime);
    }

    //Allow owner to update the round max flare amount.
    function setRoundMaxFlare(uint256 _newRoundMaxFlare) external onlyOwner {
        Round storage roundToUpdate = getLatestRound();

        if (address(this).balance < _newRoundMaxFlare) {
            revert("Insufficient balance.");
        }

        roundToUpdate.maxFlareAmount = _newRoundMaxFlare;
    }

    //Allow owner to update the round runtime.
    function setRoundRuntime(uint256 _newRoundRuntime) external onlyOwner {
        Round storage roundToUpdate = getLatestRound();

        roundToUpdate.roundRuntime = _newRoundRuntime;
    }

    //Allow owner to update the round snapshot date time.
    function setRoundSnapshotDatetime(
        uint256 _newSnapshotDatetime
    ) external onlyOwner {
        Round storage roundToUpdate = getLatestRound();

        if (block.timestamp < _newSnapshotDatetime) {
            revert("Time must be in the future.");
        }

        roundToUpdate.snapshotDatetime = _newSnapshotDatetime;
    }

    function setRoundSnapshotBlock() external onlyOwner {
        Round storage round = getLatestRound();

        if (round.snapshotDatetime > block.timestamp) {
            round.snapshotBlock = block.number;
        }
      
        round.snapshotBlock = block.number;
    }

    //Take a snapshot for the current round.
    function takeSnapshot() external onlyOwner {
        Round storage round = getLatestRound();

        round.snapshotBlock = block.number;
    }

    //Allow owner to update the round voting runtime.
    function setRoundVotingRuntime(
        uint256 _newVotingRuntime
    ) external onlyOwner {
        Round storage roundToUpdate = getLatestRound();

        roundToUpdate.votingRuntime = _newVotingRuntime;
    }

    //Get the total votes for a specifc round.
    function getTotalVotesForRound(uint256 _roundId) external view returns (uint256) {
        Proposal[] memory requestedProposals = getRoundById(_roundId).proposals;
        uint256 totalVotes = 0;

        //Iterate through proposals and count all votes.
         for (uint256 i = 0; i < requestedProposals.length; i++) {
            totalVotes += requestedProposals[i].votesReceived;
        }

        return totalVotes;
    }

    //Get a single round by ID.
    function getRoundById(uint256 _id) external view returns (Round) {
        return round[_id];
    }

    //Get the latest round.
    function getLatestRound() public view returns (Round) {
        return round[roundId];
    }

    //Get all round.
    function getAllRounds() external view returns (Round[] memory) {
        uint256 count = roundIds.length;
        Round[] memory allRounds = new Round[](count);
        for (uint256 i = 0; i < count; i++) {
            Round storage round = round[roundIds[i]];
            allRounds[i] = round;
        }
        return allRounds;
    }

    //Remove a round.
    function killRound(uint256 _roundId) external onlyOwner {
        //remove round from mapping.
        delete round[_roundId];

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

    //Get the remaining voting power for a user for a round.
    function getRemainingVotingPower(address _address) external view returns (uint256) {
        return getLatestRound().currentVotingPower[_address];
    }

    //Check if we are in a voting period. This contract and the UI will call.
    function getVotingPeriod() public view returns (bool) {
        bool inVotingPeriod = false;

        Round memory latestRound = getLatestRound();
        
        //🟠 We need a way to calculate voting start and end dates. 🟠
        uint256 votingStartDate;
        uint256 votingEndDate;

        if(block.timestamp >= votingStartDate && block.timestamp <= votingEndDate){
            inVotingPeriod = true;
        }
        
        return inVotingPeriod;
    }

    //When a round is finished, allow winner to claim.
    function roundFinished() external {
        Round memory latestRound = getLatestRound();
        Proposal[] memory latestProposals = latestRound.proposals;

        if (latestProposals.length == 0) {
            revert("No proposals exist in the round.");
        }

        //Check if round is over.
        if((latestRound.roundStarttime + latestRound.roundRuntime) < block.timestamp){
            revert("Round has not finished yet.");
        }

        //Check which proposal has the most votes.
        Proposal memory mostVotedProposal = latestProposals[0];
        for (uint256 i = 1; i < latestProposals.length; i++) {
            if (latestProposals[i].votesReceived > mostVotedProposal.votesReceived) {
                mostVotedProposal = latestProposals[i];
            }
        }

        //Add winning proposal to mappings.
        winningProposals[mostVotedProposal.receiver] = mostVotedProposal;
        winningProposalsById[latestRound.id] = mostVotedProposal;
        hasWinningProposal[mostVotedProposal.receiver] = true;
    }

    //When a round is finished, allow winner to claim. 
    function claimFunds() external {
        //Check if the wallet has won a round.
        if(!hasWinningProposal[msg.sender]){
            revert("Claimer has not won a round.");
        }

        Round storage winningProposal = winningProposals[msg.sender];
        
        //Check if the funds have already been claimed.
        if(winningProposal.fundsClaimedIfWinner){
            revert("Funds has already been claimed for winning proposal.");
        }

        address recipient = winningProposal.receiver;
        if(recipient != msg.sender){
            revert("Claimer must be the proposal recipient.");
        }

        uint256 amountRequested = winningProposal.amountRequested;
        if (address(this).balance < amountRequested) {
            revert("Insufficient balance.");
        }

        //Send amount requested to winner.
        (bool success, ) = recipient.call{value: amountRequested}("");

        require(success);
        winningProposal.fundsClaimedIfWinner = true; //Set as claimed so winner cannot reclaim for the proposal.
    }
}
