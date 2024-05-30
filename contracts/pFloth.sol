// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract pFLOTH is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 30 * 10 ** 9 * 10 ** 18; // 30 billion pFLOTH
    uint256 public constant EXCHANGE_RATE = 10000; // 1 FLR = 10,000 pFLOTH
    uint256 public constant WALLET_LIMIT = 2.5 * 10 ** 9 * 10 ** 18; // 2.5 billion pFLOTH per wallet

    uint256 public presaleEndTime;
    mapping(address => uint256) public pFLOTHBalance;

    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFLOTH") {
        presaleEndTime = block.timestamp + _presaleDuration;
    }

    event Presale(address buyer, uint256 amountFLR, uint256 amountpFLOTH);
    event Withdraw(address owner, uint256 amount);

    error PresaleEnded();
    error ExceedsSupply();
    error WalletLimitExceeded();

    function presale() external payable {
        if (presaleEndTime > block.timestamp) {
            revert PresaleEnded();
        }

        uint256 amountFLR = msg.value; // msg.value is the amount of FLR sent as native token
        uint256 amountpFLOTH = amountFLR * EXCHANGE_RATE;

        if (totalSupply() + amountpFLOTH >= MAX_SUPPLY) {
            //>= or just > ???🟠🟠🟠
            revert ExceedsSupply();
        }
        if (balanceOf(msg.sender) + amountpFLOTH >= WALLET_LIMIT) {
            //>= or just > ???🟠🟠🟠
            revert WalletLimitExceeded();
        }

        _mint(msg.sender, amountpFLOTH);
        pFLOTHBalance[msg.sender] += amountpFLOTH;

        emit Presale(msg.sender, amountFLR, amountpFLOTH);
    }

    // Withdraw function for the owner to withdraw FLR collected during presale
    //nonReentrant prevent function reentrancy vulnerabilities.
    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = owner().call{value: address(this).balance}("");

        require(success);

        emit Withdraw(msg.sender, address(this).balance);
    }
}
