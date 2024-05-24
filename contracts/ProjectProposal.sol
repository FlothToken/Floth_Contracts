// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IFloth.sol";

contract ProjectProposal is AccessControl {
    /**
     * What does the front end need/TODO
     *
     * - Create proposal function (name/amount requested/proposer and receiver set to msg.sender initially). ✅
     * - Change "batch" to "round". ✅
     * - No description on chain. ✅
     * - Remove setter for amount requested. -✅ Kyle said to now keep.
     * - Event emitted when proposal is created (creator proposal address, proposal id (make it more like a uid using keccak or something, use 16 bytes).✅
     * - Can ONLY submit proposals during "submission window" during a round. Should be locked otherwise. Front end needs to read this lock. ✅
     * - View function to get proposals and their votes and paginated, index 0 gives first x, index 1 give second x amount etc.
     * - Add winners array and remove the "accepted" bool. ✅
     * - Add AccessControl for role permissoning to the contract. Roles: ADMIN, SNAPSHOTTER, ROUND_MANAGER ✅
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

    //Admin role by default is DEFAULT_ADMIN_ROLE.
    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");
    bytes32 public constant ROUND_MANAGER_ROLE = keccak256("ROUND_MANAGER_ROLE");

    IFloth internal floth;

    constructor(address _flothAddress) {
        floth = IFloth(_flothAddress);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        uint256 votingStartDate;
        uint256 votingEndDate;
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

    //Modifiers to check for admin, shapshotter, or round manager roles.
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    modifier roundManagerOrAdmin() {
        require((hasRole(ROUND_MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender)), "Caller is not a round manager or admin");
        _;
    }
     
     modifier snapshotterManagerOrAdmin() {
        require((hasRole(SNAPSHOTTER_ROLE, msg.sender) || hasRole(ROUND_MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender)), "Caller is not a snapshotter, round manager or admin,");
        _;
    }

    //Allow admin to grant admin role to another account.
    function grantAdminRole(address account) external onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }

    //Allow admin to grant snapshotter role.
    function grantSnapshotterRole(address account) external onlyAdmin {
        grantRole(SNAPSHOTTER_ROLE, account);
    }

    //Allow admin to grant round manager role.
    function grantRoundManagerRole(address account) external onlyAdmin {
        grantRole(ROUND_MANAGER_ROLE, account);
    }

    //Add a new proposal using the users input - doesn't require to be owner.
    function addProposal(string memory _title,uint256 _amountRequested) external {
        Round memory latestRound = getLatestRound();

        //If submission window is closed, revert.
        if(!isSubmissionWindowOpen()){
            revert("Submission window is closed.");
        }
        
        //If within a voting period, revert.
        if(isVotingPeriodOpen()){
            revert("Cannot submit proposal during voting period.");
        }

        if(latestRound.maxFlareAmount < _amountRequested){
            revert("Amount requested is more than the max amount for the round.");
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

        proposals[proposalId] = newProposal;
        rounds[roundId].proposals.push(newProposal);
        rounds[roundId].proposalsPerWallet[msg.sender] += 1; //Increase proposal count for a wallet by 1.

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

        roundIds.push(roundId); //Keep track of the round ids.

        emit RoundAdded(roundId, _flrAmount, _roundRuntime);
    }

    //Allow admin or Round Manager to update the round max flare amount.
    function setRoundMaxFlare(uint256 _newRoundMaxFlare) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        if (address(this).balance < _newRoundMaxFlare) {
            revert("Insufficient balance.");
        }

        roundToUpdate.maxFlareAmount = _newRoundMaxFlare;
    }

    //Allow Admin or Round Manager to update the round runtime.
    function setRoundRuntime(uint256 _newRoundRuntime) external roundManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        roundToUpdate.roundRuntime = _newRoundRuntime;
    }

    //Allow Admin or Round Manager to update the round snapshot date time.
    function setRoundSnapshotDatetime(uint256 _newSnapshotDatetime) external snapshotterManagerOrAdmin {
        Round storage roundToUpdate = getLatestRound();

        if (block.timestamp < _newSnapshotDatetime) {
            revert("Time must be in the future.");
        }

        roundToUpdate.snapshotDatetime = _newSnapshotDatetime;
    }

    function setRoundSnapshotBlock() external snapshotterManagerOrAdmin {
        Round storage round = getLatestRound();

        if (round.snapshotDatetime > block.timestamp) {
            round.snapshotBlock = block.number;
        }
      
        round.snapshotBlock = block.number;
    }

    //Take a snapshot for the current round.
    function takeSnapshot() external snapshotterManagerOrAdmin {
        Round storage round = getLatestRound();

        if(block.timestamp <= round.snapshotDatetime){
            revert("Snapshot time not reached yet.");
        }
        if(block.timestamp > (round.roundStarttime + round.roundRuntime)){
            revert("Round has already ended.");
        }

        round.snapshotBlock = block.number;

        // Set voting period start and end times
        round.votingStartDate = block.timestamp;
        round.votingEndDate = block.timestamp + round.votingRuntime;
    }

    //Allow owner to update the round voting runtime.
    function setRoundVotingRuntime(uint256 _newVotingRuntime) external roundManagerOrAdmin {
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
        return rounds[_id];
    }

    //Get the latest round.
    function getLatestRound() public view returns (Round) {
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
    function killRound(uint256 _roundId) external roundManagerOrAdmin{
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

    //Get the remaining voting power for a user for a round.
    function voteRetrieval(uint256 _roundId, uint256 _pageNumber) external view returns (uint256[]) {
        return getLatestRound().currentVotingPower[_address];
    }

    //Get the remaining voting power for a user for a round.
    function getRemainingVotingPower(address _address) external view returns (uint256) {
        return getLatestRound().currentVotingPower[_address];
    }

    //Check if we are in a voting period. This contract and the UI will call.
    function isVotingPeriodOpen() public view returns (bool) {
        bool inVotingPeriod = false;

        Round memory latestRound = getLatestRound();

        if(block.timestamp >= latestRound.votingStartDate && block.timestamp <= latestRound.votingEndDate){
            inVotingPeriod = true;
        }
        
        return inVotingPeriod;
    }

    function isSubmissionWindowOpen() public view returns (bool) {
        Round memory latestRound = getLatestRound();
        bool isWindowOpen = false;

        if(block.timestamp < latestRound.snapshotDatetime && block.timestamp > latestRound.roundStarttime){
            isWindowOpen = true;
        }

        return isWindowOpen;
    }

    //When a round is finished, allow winner to claim.
    function roundFinished() external roundManagerOrAdmin{
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
