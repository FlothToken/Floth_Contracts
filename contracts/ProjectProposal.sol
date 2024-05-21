// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IFloth.sol";

contract ProjectProposal is Ownable{

    /**
    *
    * - Add an address to constructor argument that creates an IERC20Votes contract (Create interface which reduces the number of functions we need to pass) instead of making this it's own ERCVotes.
    *
    * Do we need a history of batches? This will determine if we need batchid tracings.
    *
    *When are we taking snapshots? doing it 2 weeks after batch opens could be tricky
    *
    *use reverts instead of require, revert errors. ✅
    *
    *change to external contracts where necessary ✅

    * add receiver address to proposal ✅
    * Add complete batch function which sender funds to receiver address. - highest votes
    * kill proposal function. ✅
    * setters for propsals - title, description, amountrequested?, receiver address. - - check that proposer = sender.
    * setter for current batch - maxFlareAmount; batchRunTime;  snapshotDatetime; snapshotBlock; votingRuntime; -- onlyowner.
    */

    IFloth internal floth;

     constructor(address _flothAddress) {
        floth = IFloth(_flothAddress);
     }

    struct Proposal{
        uint256 id;
        string title;
        string description;
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer; //The wallet that submitted the proposal.
        address receiver; //The wallet that will receive the funds.
        bool accepted;
   }

   struct Batch{
        uint256 id;
        uint256 maxFlareAmount;
        uint256 batchRunTime;
        uint256 snapshotDatetime;
        uint256 snapshotBlock;
        uint256 votingRuntime;
        Proposal[] proposals;
        mapping(address => uint256) proposalsPerWallet; //Tracks the number of proposals submitted by a wallet.
    }

   //Tracks ID number for each proposal.
   uint256 proposalId = 0;

    //Tracks ID number for each batch.
   uint256 batchId = 0;

    //Map a wallet to an array of Proposals (a wallet might submit multiple).
    // mapping(address=>Proposal[]) public proposals; //Removed and moved to the Batch struct.
    
    //Maps IDs to a proposal.
    mapping(uint256 => Proposal) proposals;
    
    //Maps IDs to a batch.
    mapping(uint256 => Batch) batches;

    //Keeps track of all batch IDs.
    uint256[] batchIds;
    
    //Notify of a new proposal being added.
    event ProposalAdded(string name, uint256 amountRequested);
    
    //Notify of a proposal being killed.
    event ProposalKilled(uint256 proposalId, string description);
    
    //Notify of a new batch being added.
    event BatchAdded(string name, uint256 amountRequested);
    
    //Notify of a batch being killed.
    event BatchKilled(uint256 batchId, string description);

    //Notify of a new proposal being added.
    event AddBatch(uint256 batchId, uint256 flrAmount, uint256 batchRuntime);

    //Notify of votes added to a proposal.
    event VotesAdded(uint256 proposalId, address wallet, uint256 numberofVotes);

    //Add a new proposal using the users input - doesn't require to be owner.
    function addProposal(string memory _title, string memory _description, uint256 _amountRequested, address _receiver) external{
        proposalId++;

        Proposal memory newProposal = Proposal(proposalId, _title, _description, _amountRequested, msg.sender, _receiver, false);

        // proposals[msg.sender].push(newProposal); //Removed and moved to Batch struct.
        proposals[proposalId] = newProposal;
        batches[batchId].proposals.push(newProposal);
        batches[batchId].proposalsPerWallet[msg.sender] += 1; //Increase proposal count for a wallet by 1.

        emit ProposalAdded(_title, _amountRequested);
    }

     //Get a single proposal by ID.
    function getProposalById(uint256 _id) external view returns (Proposal){
        return proposals[_id];
    }

    //Votes for a proposal within a batch.
    function addVotesToProposal(uint256 _proposalId, uint256 _numberOfVotes) external{
        //Check if the user has FLOTH and their voting power if greater than or equal to their votes.
        if(floth.balanceOf(msg.sender) <= 0){
            revert("User doesn't have FLOTH.");

        } else if(getVotingPower(msg.sender) >= _numberOfVotes){
            revert("Number of votes error.");
        }

        Proposal storage proposal = getProposalById(_proposalId);
        proposal.votesReceived += _numberOfVotes;

        emit VotesAdded(_proposalId, msg.sender, _numberOfVotes);
    }

    //Remove a proposal from a batch.
    function killProposal(uint256 _proposalId) external{
        //Only the proposal owner or the contract owner can delete.
        if(msg.sender != proposals[_proposalId].proposer || msg.sender != owner()){
            revert("User must be owner of proposal or owner.");
        }

        //remove proposal from mapping.
        delete proposals[_proposalId]; 

        emit ProposalKilled(_proposalId, "Proposal killed successfully.");
    }

    //Get all the proposals by address.
    // function getProposalsByAddress(address _address) public view returns (Proposal[]){
    //     return proposals[_address];
    // }

    //Add a new batch (round).
    function addBatch(uint256 _flrAmount, uint256 _batchRuntime, uint256 _snapshotDatetime, uint256 _votingRuntime) external onlyOwner{
        batchId++;
        // uint256 snapshotBlock = block.number; // now handled by updateLatestBatch().

        Batch storage newBatch = batches[batchId]; //Needed for mappings in structs to work.
        newBatch.id = batchId;
        newBatch.maxFlareAmount = _flrAmount;
        newBatch.batchRunTime = _batchRuntime;
        newBatch.snapshotDatetime = _snapshotDatetime;
        newBatch.snapshotBlock = block.number;
        newBatch.votingRuntime = _votingRuntime;
        newBatch.proposals = [];

        batchIds.push(batchId); //Keep track of the batch ids.

        emit BatchAdded(batchId, _flrAmount, _batchRuntime);
    }

     //Get a single batch by ID.
    function getBatchById(uint256 _id) external view returns (Batch){
        return batches[_id];
    }

    //Get the latest batch.
    function getLatestBatch() public view returns (Batch){
        return batches[batchId];
    }

     //Get all batches.
    function getAllBatches() external view returns (Batch[] memory){
        uint256 count = batchIds.length;
        Batch[] memory allBatches = new Batch[](count);
        for (uint256 i = 0; i < count; i++) {
            Batch storage batch = batches[batchIds[i]];
            allBatches[i] = batch;
        }
        return allBatches;
    }

    //After the snapshot date time has passed for a batch, set the snapshot block.
    function updateLatestBatch() external onlyOwner{
        Batch storage batch = getLatestBatch();

        if(batch.snapshotDatetime > block.timestamp){
            batch.snapshotBlock = block.number;
        }
    }

    //Remove a batch.
    function killBatch(uint256 _batchId) external onlyOwner{
        //remove batch from mapping.
        delete batches[_batchId]; 

        //remove batch id from array.
        for (uint256 i = 0; i < batchIds.length; i++) {
            if (batchIds[i] == _batchId) {
                batchIds[i] = batchIds[batchIds.length - 1];
                batchIds.pop();
                break;
            }
        }
        emit BatchKilled(_batchId, "Batch killed successfully.");
    }

    //Get voting power for a user.
    function getVotingPower(address _address) external view returns (uint256){
        uint256 snapshotBlock = getLatestBatch().snapshotBlock;

        uint256 votingPower = floth.getPastVotes(_address, snapshotBlock);

        return votingPower;
    }
}
