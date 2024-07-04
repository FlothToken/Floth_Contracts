// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Presale Floth Token
 * @author Ethereal Labs
 */

// ERC20 contract for presale floth token
contract pFloth is ERC20, Ownable, ReentrancyGuard {
    //Constants
    uint256 public constant MAX_SUPPLY = 30 * 10 ** 9 * 10 ** 18; // 30 billion pFLOTH
    uint256 public constant EXCHANGE_RATE = 10000; // 1 FLR = 10,000 pFLOTH
    uint256 public constant WALLET_LIMIT = 2.5 * 10 ** 9 * 10 ** 18; // 2.5 billion pFLOTH per wallet

    // Variables
    uint256 public presaleEndTime;

    // Mappings
    mapping(address => uint256) public pFLOTHBalance;

    /**
     * Constructor for the pFLOTH contract
     * @param _presaleDuration The duration of the presale in seconds
     */
    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFLOTH") {
        presaleEndTime = block.timestamp + _presaleDuration;
    }

    // Events
    event Presale(address buyer, uint256 amountFLR, uint256 amountpFLOTH);
    event Withdraw(address owner, uint256 amount);

    // Errors
    error PresaleEnded();
    error ExceedsSupply();
    error WalletLimitExceeded();
    error TransferFailed();

    /**
     * @dev Function to buy pFLOTH during the presale
     */
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

        pFLOTHBalance[msg.sender] += amountpFLOTH;

        _mint(msg.sender, amountpFLOTH);

        emit Presale(msg.sender, amountFLR, amountpFLOTH);
    }

    /**
     * Function to extend the presale duration
     * @param _duration The duration in seconds to extend the presale by
     * Only the owner can call this function
     */
    function extendPresale(uint256 _duration) external onlyOwner {
        presaleEndTime += _duration;
    }

    /**
     * Function to withdraw FLR collected during the presale
     * Only the owner can call this function
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 _amount = address(this).balance;
        (bool success, ) = owner().call{value: _amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, _amount);
    }
}
