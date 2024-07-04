// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//mandem
contract pFLOTHTest is ERC20, Ownable, ReentrancyGuard {
    uint256 public MAX_SUPPLY = 30 * 10 ** 9 * 10 ** 18; // 30 billion pFLOTH
    uint256 public constant EXCHANGE_RATE = 10000; // 1 FLR = 10,000 pFLOTH
    uint256 public WALLET_LIMIT = 2.5 * 10 ** 9 * 10 ** 18; // 2.5 billion pFLOTH per wallet

    uint256 public presaleEndTime;
    mapping(address => uint256) public pFLOTHBalance;

    constructor(
        uint256 _presaleDuration
    ) ERC20("Presale FlothTest", "pFLOTHTest") {
        presaleEndTime = block.timestamp + _presaleDuration;
    }

    event Presale(address buyer, uint256 amountFLR, uint256 amountpFLOTH);
    event Withdraw(address owner, uint256 amount);

    error PresaleEnded();
    error ExceedsSupply();
    error WalletLimitExceeded();
    error TransferFailed();

    function presale() external payable {
        if (block.timestamp > presaleEndTime) {
            revert PresaleEnded();
        }

        uint256 amountFLR = msg.value; // msg.value is the amount of FLR sent as native token
        uint256 amountpFLOTH = amountFLR * EXCHANGE_RATE;

        if (totalSupply() + amountpFLOTH > MAX_SUPPLY) {
            revert ExceedsSupply();
        }
        if (balanceOf(msg.sender) + amountpFLOTH > WALLET_LIMIT) {
            revert WalletLimitExceeded();
        }

        _mint(msg.sender, amountpFLOTH);
        pFLOTHBalance[msg.sender] += amountpFLOTH;

        emit Presale(msg.sender, amountFLR, amountpFLOTH);
    }

    // Helper function for testing purposes
    function setTotalSupply(uint256 _supply) external onlyOwner {
        MAX_SUPPLY = _supply;
    }

    function setWalletLimit(uint256 _limit) external onlyOwner {
        WALLET_LIMIT = _limit;
    }

    // Withdraw function for the owner to withdraw FLR collected during presale
    //nonReentrant prevent function reentrancy vulnerabilities.
    function withdraw() external onlyOwner nonReentrant {
        uint256 _amount = address(this).balance;
        (bool success, ) = owner().call{value: _amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, _amount);
    }
}
