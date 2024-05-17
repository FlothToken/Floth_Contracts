// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract pFLOTH is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 30 * 10 ** 9 * 10 ** 18; // 30 billion pFLOTH
    uint256 public constant EXCHANGE_RATE = 10000; // 1 FLR = 10,000 pFLOTH
    uint256 public constant WALLET_LIMIT = 2.5 * 10 ** 9 * 10 ** 18; // 2.5 billion pFLOTH per wallet

    uint256 public presaleEndTime;
    mapping(address => uint256) public pFLOTHBalance;

    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFLOTH") {
        presaleEndTime = block.timestamp + _presaleDuration;
    }

    function presale() external payable {
        require(block.timestamp < presaleEndTime, "Presale has ended");
        uint256 amountFLR = msg.value; // msg.value is the amount of FLR sent as native token
        uint256 amountpFLOTH = amountFLR * EXCHANGE_RATE;

        require(
            totalSupply() + amountpFLOTH <= MAX_SUPPLY,
            "Exceeds max supply"
        );
        require(
            balanceOf(msg.sender) + amountpFLOTH <= WALLET_LIMIT,
            "Exceeds wallet limit"
        );

        _mint(msg.sender, amountpFLOTH);
        pFLOTHBalance[msg.sender] += amountpFLOTH;
    }

    // Withdraw function for the owner to withdraw FLR collected during presale
    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
