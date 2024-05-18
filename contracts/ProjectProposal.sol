// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";


contract ProjectProposal is Ownable {

    struct Proposal{
        uint256 id;
        string title;
        string description;
        uint256 amountRequested;
        uint256 votesReceived;
        address proposer; //The wallet that submitted the proposal.
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
    }

   //Tracks ID number for each proposal.
   uint256 proposalId = 0;

    //Tracks ID number for each batch.
   uint256 batchId = 0;

    //Map a wallet to an array of Proposals (a wallet might submit multiple).
    mapping(address=>Proposal[]) public proposals; 
    
    //Maps IDs to a propsal.
    mapping(uint256 => Proposal) public proposalsById;
    
    //Maps IDs to a batch.
    mapping(uint256 => Batch) public batches;

    //Keeps track of all batch IDs.
    uint256[] public batchIds;
    
    //Notify of a new proposal being added.
    event ProposalAdded(string name, uint256 amountRequested);
    
    //Notify of a new batch being added.
    event BatchAdded(string name, uint256 amountRequested);
    
    //Notify of a batch being killed.
    event BatchKilled(uint256 batchId, string description);

    //Notify of a new proposal being added.
    event AddBatch(uint256 batchId, uint256 _flrAmount, uint256 _batchRuntime);

    //Add a new proposal using the users input - doesn't require to be owner.
    function addProposal(string memory _title, string memory _description, uint256 _amountRequested) public{
        proposalId++;

        Proposal memory newProposal = Proposal(proposalId, _title, _description, _amountRequested, msg.sender, false);

        proposals[msg.sender].push(newProposal);
        proposalsById[proposalId] = newProposal;
        batches[batchId].proposals.push(newProposal);

        emit ProposalAdded(_title, _amountRequested);
    }

     //Get a single proposal by ID.
    function getProposalById(uint256 _id) public view returns (Proposal){
        return proposalsById[_id];
    }

    //Get all the proposals by address.
    function getProposalsByAddress(address _address) public view returns (Proposal[]){
        return proposals[_address];
    }

    //Add a new batch (round).
    function addBatch(uint256 _flrAmount, uint256 _batchRuntime, uint256 _snapshotDatetime, uint256 _votingRuntime) public onlyOwner{
        batchId++;
        uint256 snapshotBlock = block.number;

        Batch memory newBatch = Batch(batchId, _flrAmount, _batchRuntime, _snapshotDatetime, snapshotBlock, _votingRuntime, []);
        batches[batchId] = newBatch;

        batchIds.push(batchId); //keep track of the batch ids.

        emit BatchAdded(batchId, _flrAmount, _batchRuntime);
    }

     //Get a single batch by ID.
    function getBatchById(uint256 _id) public view returns (Batch){
        return batches[_id];
    }

    //Get the latest batch.
    function getLatestBatch() public view returns (Batch){
        return batches[batchId];
    }

     //Get all batches.
    function getAllBatches() public view returns (Batch[] memory){
        uint256 count = batchIds.length;
        Batch[] memory allBatches = new Batch[](count);
        for (uint256 i = 0; i < count; i++) {
            Batch storage batch = batches[batchIds[i]];
            allBatches[i] = batch;
        }
        return allBatches;
    }

    //Remove a batch.
    function killBatch(uint256 _batchId) public onlyOwner{
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
}
