// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
import "./IFloth.sol";
import "./IFlothPass.sol";

/**
 * @title ProjectProposalUpgrade contract for the Floth protocol
 * @author Ethereal Labs
 */
contract ProjectProposalUpgrade is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
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

    function initialize(address _flothAddress, address _flothPassAddress) public initializer {
        __AccessControl_init();
        __ProjectProposal_init(_flothAddress, _flothPassAddress);
    }

    /**
     * Initializer for the ProjectProposalUpgrade contract
     * @param _flothAddress The address of the Floth contract
     * @param _flothPassAddress The address of the FlothPass contract
     */

    function __ProjectProposal_init(address _flothAddress, address _flothPassAddress) internal initializer {
        if (_flothAddress == address(0) || _flothPassAddress == address(0)) {
            revert ZeroAddress();
        }
        floth = IFloth(_flothAddress);
        flothPass = IFlothPass(_flothPassAddress);

        nftMultiplier = 200;

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
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256[] proposalIds;
        bool isActive;
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

    //Maps IDs to a proposal.
    mapping(uint256 => Proposal) public proposals;

    //Maps address to a bool for proposal winners.
    mapping(address => bool) public hasWinningProposal;

    //Maps winning address to winning proposals.
    mapping(address => Proposal[]) public winningProposals;

    //Maps winning roundID to winning proposals.
    mapping(uint256 => Proposal) public winningProposalByRoundId;

    //Maps IDs to a round.
    mapping(uint256 => Round) public rounds;

    // Mappings of mappings //

    // Number of proposals per wallet for a specific round.
    mapping(address => mapping(uint256 => uint256))
        public proposalsPerWalletPerRound; // (address => (roundId => count))

    // Mapping to check if wallet has voted in particular round.
    mapping(address => mapping(uint256 => bool)) public hasVotedByRound; // (address => (roundId => voted))

    // Voting power for a wallet in a specific round.
    mapping(address => mapping(uint256 => uint256)) public votingPowerByRound; // (address => (roundId => power))

    // Tracks the proposals that an address has voted on.
    mapping(address => mapping(uint256 => Votes[])) public votedOnProposals; // (address => (roundId => Votes[]))

    // Tracks the FlothPass voting power at a snapshot block.
    mapping(uint256 => mapping(address => uint256)) public flothPassesOwned; // (snapshotBlock => (FlothPass Owner => number of FlothPass' owned))

    //Keeps track of all round IDs.
    uint256[] roundIds;

    /**
     * Events for the ProjectProposalUpgrade contract
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

    /**
     * Error messages for the ProjectProposalUpgrade contract
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

    //Modifiers for the ProjectProposalUpgrade contract
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

        if(!isVotingPeriodOpen()){
            Round storage getRound = getLatestRound();

            if(block.timestamp > getRound.expectedSnapshotDatetime && getRound.snapshotDatetime == 0){
                revert VotingPeriodBeginsSoon();
            }else{
                revert VotingPeriodClosed();
            }
        }

        Proposal storage proposal = proposals[_proposalId];
        Round storage currentRound = getLatestRound();

        bool hasVoted = hasVotedByRound[msg.sender][currentRound.id];
        uint256 currentVotingPower;

        //If they haven't voted yet, set votingPowerByRound, else retrieve current voting power.
        if(!hasVoted){
            currentVotingPower = getFlothVotingPower(msg.sender) + getFlothPassVotingPower(msg.sender);
            votingPowerByRound[msg.sender][currentRound.id] = currentVotingPower;
        }else{
            currentVotingPower = votingPowerByRound[msg.sender][currentRound.id];
        }

        //If voting for the Abstain proposal.
        if (_proposalId == currentRound.abstainProposalId) {
            //Abstain vote can only be given to one proposal.
            
            Votes[] memory votesByUser = votedOnProposals[msg.sender][currentRound.id]; 
            //Remove votes on other proposals.
            if(votesByUser.length > 0){
                for (uint256 i = 0; i < votesByUser.length; i++) {
                    //Remove votes from proposal.
                    proposals[votesByUser[i].proposalId].votesReceived -= votesByUser[i].voteCount;
                }
            }

             //Voting power re-retrieved as may be reduced if previously voted.
            uint256 votingPower = getFlothVotingPower(msg.sender) + getFlothPassVotingPower(msg.sender);
            
            proposal.votesReceived += votingPower; //Give all voting power to abstain proposal.
            votingPowerByRound[msg.sender][currentRound.id] = 0; //All voting power is removed.
            hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.
        
        } else {

            console.log("Current voting power: %d", currentVotingPower);

            //Check if the user doesn't have any voting power set, revert. Checked here to let users call abstain if no power left.
            if (currentVotingPower == 0) {
                revert InvalidVotingPower();
            } 
            
            //If the user doesn't have enough voting power, stop them from voting.
            if (currentVotingPower < _numberOfVotes) {
                revert InsufficientVotingPower();
            }

            //Vote is for non-abstain proposal.
            if(_proposalId != currentRound.abstainProposalId) {            
                proposal.votesReceived += _numberOfVotes; //Increase proposal vote count.
                votingPowerByRound[msg.sender][currentRound.id] -= _numberOfVotes; //Reduce voting power in a round.
                hasVotedByRound[msg.sender][currentRound.id] = true; //Set that the user has voted in a round.

                //Create votes struct object of the users vote.
                Votes memory newVote = Votes({
                    proposalId: _proposalId,
                    voteCount: _numberOfVotes
                });

                votedOnProposals[msg.sender][currentRound.id].push(newVote); //Track proposal votes given by a user.
            }
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

        Votes[] storage votesByUser = votedOnProposals[msg.sender][currentRound.id];

        for (uint256 i = 0; i < votesByUser.length; i++) {
            if(_proposalId == votesByUser[i].proposalId){
                uint256 votesToRemove = votesByUser[i].voteCount;
    
                Proposal storage proposal = proposals[_proposalId];
                proposal.votesReceived -= votesToRemove; //Remove votes given to proposal.
                votingPowerByRound[msg.sender][currentRound.id] += votesToRemove; //Give voting power back to user.

                // Copy last element to current element so last element can be popped
                votesByUser[i] = votesByUser[votesByUser.length - 1];

                // Remove the struct.
                votesByUser.pop();

                if(votesByUser.length == 0){
                    hasVotedByRound[msg.sender][currentRound.id] = false; //Remove users has voted status.
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
        Round storage currentRound = getLatestRound();

        //Check if the user hasn't voted.
        if (!hasVotedByRound[msg.sender][currentRound.id]) {
            revert UserVoteNotFound();
        }

        Votes[] storage votesByUser = votedOnProposals[msg.sender][currentRound.id];

        for (uint256 i = 0; i < votesByUser.length; i++) {
            uint256 votesToRemove = votesByUser[i].voteCount;

            Proposal storage proposal = proposals[votesByUser[i].proposalId];

            proposal.votesReceived -= votesToRemove; //Remove votes given to proposal.
            votingPowerByRound[msg.sender][currentRound.id] += votesToRemove; //Give voting power back to user.
        }

        // Clear the votes mapping.
        delete votedOnProposals[msg.sender][currentRound.id];

        if(votesByUser.length == 0){
            hasVotedByRound[msg.sender][currentRound.id] = false; //Remove users has voted status.

            emit AllVotesRemoved(msg.sender);
        }
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
        newRound.snapshotBlock = 0;
        newRound.snapshotDatetime = 0; 
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

        if(round.snapshotBlock == 0){
            round.snapshotBlock = block.number;
            round.snapshotDatetime = block.timestamp; //Set the actual snapshot time.
            _getFlothPassesOwned(round.snapshotBlock);
        }

        emit SnapshotTaken(round.id, round.snapshotBlock);
    }

    function _getFlothPassesOwned(uint256 _snapshotBlock) internal {
        uint256 numberMinted = flothPass.getNumberMinted();

        //Starts at 1 as the first FlothPass minted is 1 not 0.
        for (uint256 i = 1; i <= numberMinted; i++) {
            address owner = flothPass.ownerOf(i);

            //Update the mapping with the number of FlothPass' owned by an address.
            flothPassesOwned[_snapshotBlock][owner]++;
        }
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
            revert RoundIdOutOfRange();
        }
        return rounds[_id];
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

        Round storage round = rounds[_roundId];
        
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
        return rounds[roundId];
    }

    /**
     * Function to get all rounds
     */
    function getAllRounds() external view returns (Round[] memory) {
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

        //Send funds back to grant fund wallet.
        (bool success, ) = floth.getGrantFundWallet().call{value: maxFlareAmount}("");
        require(success);

        emit RoundKilled(_roundId);
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

        if(rounds[_roundId].proposalIds.length <= (endIndex-1)){
            endIndex = rounds[_roundId].proposalIds.length;
        }

        uint256 resultSize = endIndex - startIndex;
        Votes[] memory voteRetrievals = new Votes[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            Proposal storage proposal = proposals[
                rounds[_roundId].proposalIds[startIndex + i]
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
        return votingPowerByRound[_address][roundId];
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
        uint256 nftVotingPower = flothPassesOwned[snapshotBlock][_address] * nftMultiplier;

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
        Round memory latestRound = getLatestRound();

        if(latestRound.snapshotBlock == 0){
            return 0;
        }
        uint256 snapshotBlock = latestRound.snapshotBlock;

        return flothPass.getPastVotes(_address, snapshotBlock) * nftMultiplier;
    }

    /**
     * Check if the voting period is open
     */
    function isVotingPeriodOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
        
        if(latestRound.snapshotDatetime == 0){
            return false;
        }

        // Check if the current time is within the voting period
        if (block.timestamp >= latestRound.snapshotDatetime) {
            if (block.timestamp <= latestRound.roundStartDatetime + latestRound.roundRuntime) {
                return true;
            }
        }
        
        return false;
    }
    

    /**
     * Check if the submission window is open
     */
    function isSubmissionWindowOpen() public view returns (bool) {
        Round storage latestRound = getLatestRound();
       
        return
            block.timestamp < latestRound.expectedSnapshotDatetime &&
            block.timestamp >= latestRound.roundStartDatetime;
    }
    
    //
    /**
     * Function to finish a round
     */
    function roundFinished() external roundManagerOrAdmin {
        Round storage latestRound = getLatestRound();

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
        winningProposals[mostVotedProposal.receiver].push(mostVotedProposal);
        winningProposalByRoundId[latestRound.id] = mostVotedProposal;
        hasWinningProposal[mostVotedProposal.receiver] = true;

        //Check if the winning proposal is the abstain proposal.
        if (mostVotedProposal.id == latestRound.abstainProposalId) {
            //Set as claimed so winner cannot reclaim for the proposal.
            mostVotedProposal.fundsClaimed = true; 
            winningProposalByRoundId[mostVotedProposal.roundId].fundsClaimed = true;
            proposals[mostVotedProposal.id].fundsClaimed = true;

            //Send funds back to grant fund wallet.
            (bool success, ) = floth.getGrantFundWallet().call{value: latestRound.maxFlareAmount}("");
            require(success);
        }

        emit RoundCompleted(latestRound.id, mostVotedProposal.id);
    }

    /**
     * @dev Currently if a user has a winning proposal in multiple 
     * rounds they have to claim one at once.
     * Function to claim funds for a winning proposal
     */
    function claimFunds(uint256 _roundId) external nonReentrant {

        if (!hasWinningProposal[msg.sender]) {
            revert InvalidClaimer();
        }

        Proposal[] storage usersWinningProposals = winningProposals[msg.sender];

        for (uint256 i = 0; i < usersWinningProposals.length; i++) {
            if(!usersWinningProposals[i].fundsClaimed && usersWinningProposals[i].roundId == _roundId){
                Round storage claimRound = rounds[_roundId];

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

                //Set as claimed so winner cannot reclaim for the proposal.
                usersWinningProposals[i].fundsClaimed = true; 
                winningProposalByRoundId[usersWinningProposals[i].roundId].fundsClaimed = true;
                proposals[usersWinningProposals[i].id].fundsClaimed = true;

                //Send amount requested to winner.
                (bool success, ) = usersWinningProposals[i].receiver.call{value: amountRequested}("");
                require(success);

                emit FundsClaimed(usersWinningProposals[i].id, msg.sender, amountRequested);
                return;
            }
        }
    }

    /**
     * Function to manually check if winning proposal hasn't been claimed.
     */
    function reclaimFunds(uint256 _roundId) external roundManagerOrAdmin {
        Proposal storage proposal = winningProposalByRoundId[_roundId];
        Round memory claimRound = getRoundById(_roundId);

        if(!proposal.fundsClaimed){
            uint256 daysPassed = (block.timestamp - claimRound.roundStartDatetime + claimRound.roundRuntime) / 86400;

            if (daysPassed > 30) {
                //Set bool for funds claimed to true in both mappings.
                proposal.fundsClaimed = true; 

                Proposal[] storage userProposals = winningProposals[proposal.receiver];
                for (uint256 i = 0; i < userProposals.length; i++) {
                    if (userProposals[i].id == proposal.id) {
                        userProposals[i].fundsClaimed = true;
                        proposals[userProposals[i].id].fundsClaimed = true;
                    }
                }
                
                // Send amount to the grant wallet.
                (bool success, ) = floth.getGrantFundWallet().call{value: proposal.amountRequested}("");
                require(success);

                emit FundsReclaimed(proposalId, floth.getGrantFundWallet(), proposal.amountRequested);
            }
        }
    }

    /**
     * Function to get all winning proposals by roundID that have 
     * passed the claiming period and haven't been claimed.
     */
    function getUnclaimedWinningRoundIds() view external roundManagerOrAdmin returns (uint256[] memory) {
        // Get the count of unclaimed proposals
        uint256 count = 0;
        for (uint256 i = 1; i <= roundIds.length; i++) {
            Proposal storage proposal = winningProposalByRoundId[i];
            Round memory claimRound = getRoundById(i);

            if (!proposal.fundsClaimed) {
                uint256 daysPassed = (block.timestamp - claimRound.roundStartDatetime + claimRound.roundRuntime) / 86400;
                if (daysPassed > 30) {
                    count++;
                }
            }
        }

        // Initialize the memory array with the correct count
        uint256[] memory unclaimedWinningRoundIds = new uint256[](count);
        uint256 index = 0; // Index for the memory array

        // Populate the memory array with unclaimed round IDs
        for (uint256 i = 1; i <= roundIds.length; i++) {
            Proposal storage proposal = winningProposalByRoundId[i];
            Round memory claimRound = getRoundById(i); // Define claimRound here as well

            if (!proposal.fundsClaimed) {
                uint256 daysPassed = (block.timestamp - claimRound.roundStartDatetime + claimRound.roundRuntime) / 86400;

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

    /**
     * Test function to see if contract was upgraded.
     */
    function isContractUpgraded() external pure returns (string memory) {
        return "Contract is upgraded";
    }
}
