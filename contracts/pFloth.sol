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
    uint256 private constant BILLION = 1_000_000_000;
    uint256 public constant MAX_SUPPLY = 30 * BILLION * 10**decimals();
    uint256 public constant WALLET_LIMIT = 25 * (BILLION / 10) * 10**decimals(); // 2.5 billion
    uint256 public constant EXCHANGE_RATE = 10_000;

    // Pack variables together to save storage slots
    struct PresaleInfo {
        uint256 startTime;
        uint256 endTime;
        bool paused;
    }
    
    PresaleInfo public presaleInfo;

    // Mappings
    mapping(address => uint256) public pFLOTHBalance;
    mapping(address => mapping(address => uint256)) public tokenSenders; // token => sender => amount

    /**
     * @dev Constructor for the pFloth contract
     * @param _presaleDuration The duration of the presale in seconds
     */
    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFloth") {
        presaleInfo.startTime = block.timestamp;
        presaleInfo.endTime = block.timestamp + _presaleDuration;
        emit PresaleStarted(presaleInfo.startTime, presaleInfo.endTime);
    }

    // Events
    event PresaleStarted(uint256 startTime, uint256 endTime);
    event PresaleExtended(uint256 oldEndTime, uint256 newEndTime);
    event PresalePaused(bool isPaused);
    event Presale(
        address indexed buyer,
        uint256 amountFLR,
        uint256 amountpFLOTH,
        uint256 timestamp
    );
    event TokenRecovered(address token, uint256 amount);
    event Withdraw(address owner, uint256 amount);
    event TokenReturned(address indexed token, address indexed sender, uint256 amount);

    // Errors
    error PresaleEnded();
    error ExceedsSupply();
    error TransferFailed();
    error PresaleNotStarted();
    error PresaleIsPaused();
    error ExceedsWalletLimit();
    error InvalidRecoveryToken();
    error InvalidRecoveryAmount();
    error UnauthorizedRecovery();

    // Modifiers
    modifier onlyDuringPresale() {
        if (block.timestamp < presaleInfo.startTime) revert PresaleNotStarted();
        if (block.timestamp > presaleInfo.endTime) revert PresaleEnded();
        if (presaleInfo.paused) revert PresaleIsPaused();
        _;
    }

    /**
     * @dev Main presale function to purchase pFLOTH tokens
     */
    function presale() external payable onlyDuringPresale nonReentrant {
        
        uint256 amountpFLOTH = msg.value * EXCHANGE_RATE;
        
        if (totalSupply() + amountpFLOTH > MAX_SUPPLY) revert ExceedsSupply();
        if (pFLOTHBalance[msg.sender] + amountpFLOTH > WALLET_LIMIT) revert ExceedsWalletLimit();
        
        pFLOTHBalance[msg.sender] += amountpFLOTH;
        _mint(msg.sender, amountpFLOTH);

        emit Presale(
            msg.sender,
            msg.value,
            amountpFLOTH,
            block.timestamp
        );
    }

    /**
     * @dev Function to extend the presale duration
     * @param _duration The duration in seconds to extend the presale by
     * Only the owner can call this function
     */
    function extendPresale(uint256 _duration) external onlyOwner {
        uint256 oldEndTime = presaleInfo.endTime;
        presaleInfo.endTime += _duration;
        emit PresaleExtended(oldEndTime, presaleInfo.endTime);
    }

    /**
     * @dev Toggle emergency pause functionality
     * Only the owner can call this function
     * Emits a PresalePaused event
     */
    function togglePause() external onlyOwner {
        presaleInfo.paused = !presaleInfo.paused;
        emit PresalePaused(presaleInfo.paused);
    }

    /**
     * @dev Function to withdraw FLR collected during the presale
     * Only the owner can call this function
     * Implements nonReentrant pattern for security
     * Emits a Withdraw event upon successful withdrawal
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 _amount = address(this).balance;
        (bool success, ) = owner().call{value: _amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @dev Override the token transfer hook to track incoming ERC20 tokens
     * @param token The token being transferred
     * @param sender The address sending the tokens
     * @param amount The amount of tokens being transferred
     */
    function _beforeTokenTransfer(
        address token,
        address sender,
        uint256 amount
    ) internal override {
        if (token != address(this)) { // Only track non-pFLOTH tokens
            tokenSenders[token][sender] += amount;
        }
    }

    /**
     * @dev Recover ERC20 tokens and return them to their original sender
     * @param token The address of the token to recover
     * @param sender The address that originally sent the tokens
     * Anyone can recover their own tokens, owner can recover for others
     * Cannot be used to recover pFLOTH tokens
     */
    function returnERC20ToSender(
        address token,
        address sender
    ) external nonReentrant {
        // Only allow msg.sender to recover their own tokens, or owner to recover for anyone
        // TODO: Discuss the ramifications of this owner being able to recover for anyone.
        if (msg.sender != sender && msg.sender != owner()) revert UnauthorizedRecovery();
        if (token == address(this)) revert InvalidRecoveryToken();
        
        uint256 amount = tokenSenders[token][sender];
        if (amount == 0) revert InvalidRecoveryAmount();
        
        tokenSenders[token][sender] = 0; // Reset the tracked amount
        IERC20(token).transfer(sender, amount);
        emit TokenReturned(token, sender, amount);
    }

    /**
     * @dev View function to get remaining supply of pFLOTH tokens
     * @return uint256 The number of tokens still available for presale
     */
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    /**
     * @dev View function to get remaining time in the presale
     * @return uint256 The number of seconds remaining in the presale
     * Returns 0 if presale has ended
     */
    function presaleTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= presaleInfo.endTime) return 0;
        return presaleInfo.endTime - block.timestamp;
    }

    /**
     * @dev View function to get comprehensive presale statistics
     * @return totalRaised The total amount of FLR raised
     * @return totalMinted The total amount of pFLOTH tokens minted
     * @return remaining The remaining amount of pFLOTH tokens available
     * @return isActive Whether the presale is currently active
     */
    function getPresaleStats() external view returns (
        uint256 totalRaised,
        uint256 totalMinted,
        uint256 remaining,
        bool isActive
    ) {
        totalRaised = address(this).balance;
        totalMinted = totalSupply();
        remaining = MAX_SUPPLY - totalMinted;
        isActive = block.timestamp >= presaleInfo.startTime && 
                   block.timestamp <= presaleInfo.endTime && 
                   !presaleInfo.paused;
    }
}
