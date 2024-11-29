// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Presale Floth Token
 * @author Ethereal Labs
 */

// ERC20 contract for presale floth token
contract pFloth is ERC20, Ownable, ReentrancyGuard {

    // More readable and gas efficient way to write large numbers
    uint256 private constant DECIMALS = 18;
    uint256 private constant BILLION = 1_000_000_000;
    uint256 public constant MAX_SUPPLY = 30 * BILLION * 10**DECIMALS;
    uint256 public constant WALLET_LIMIT = 25 * (BILLION / 10) * 10**DECIMALS; // 2.5 billion
    uint256 public constant EXCHANGE_RATE = 10_000;
    uint256 public constant MIN_PURCHASE = 100_000_000 gwei; // 0.1 FLR

    // Pack variables together to save storage slots
    struct PresaleInfo {
        uint64 startTime;
        uint64 endTime;
        bool paused;
        bool finalized;
    }
    PresaleInfo public presaleInfo;

    // Mappings
    mapping(address => uint256) public pFLOTHBalance;

    /**
     * Constructor for the pFloth contract
     * @param _presaleDuration The duration of the presale in seconds
     */
    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFloth") {
        presaleInfo.startTime = uint64(block.timestamp);
        presaleInfo.endTime = uint64(block.timestamp + _presaleDuration);
    }

    // Events
    event Presale(address buyer, uint256 amountFLR, uint256 amountpFLOTH);
    event Withdraw(address owner, uint256 amount);

    // Errors
    error PresaleEnded();
    error ExceedsSupply();
    error WalletLimitExceeded();
    error TransferFailed();
    error PresaleNotActive();

    /**
     * @dev Function to buy pFLOTH during the presale
     */
    function presale() external payable {
        if (block.timestamp > presaleInfo.endTime) {
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
        presaleInfo.endTime += _duration;
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
