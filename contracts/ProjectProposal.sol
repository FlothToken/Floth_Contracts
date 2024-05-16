// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract ProjectProposal {

    struct Proposal{
        uint256 id;
        string title;
        string description;
        uint256 amountRequested; 
        address proposer; //The wallet that submitted the proposal.
        bool accepted;
   }

   //Wallet address of the contract initiator.
   address public owner;

   //Tracks ID number for each proposal.
   uint256 proposalId = 0;

    //Map a wallet to an array of Proposals (a wallet might submit multiple).
    mapping(address=>Proposal[]) public proposals; 
    
    //Get one proposal by propsal ID.
    mapping(uint256 => Proposal) public proposalById;
    
    //Notify of a new proposal being added.
    event Add(string name, uint256 amountRequested);

    //Sets the owner to the wallet that initiates the contract.
    constructor(){
        owner = msg.sender;
    }

    //Ensures that only the owner of the smart contract is acting upon it.
    modifier onlyOwner(){
        require(msg.sender == owner, "Error: You are not the owner.");
        _;
    }

    //Add a new proposal using the users input - doesn't require to be owner.
    function addProposal(string memory _title, string memory _description, uint256 _amountRequested) public{
        proposalId++;

        Proposal memory newProposal = Proposal(proposalId, _title, _description, _amountRequested, msg.sender, false);

        proposals[msg.sender].push(newProposal);
        proposalById[proposalId] = newProposal;

        emit Add(_title, _amountRequested);
    }

     //Get a single proposal by ID.
    function getProposalById(uint256 _id) public view returns (Proposal){
        return proposalById[_id];
    }

    //Get all the proposals by address.
    function getProposalsByAddress(address _address) public view returns (Proposal[]){
        return proposals[_address];
    }
}
