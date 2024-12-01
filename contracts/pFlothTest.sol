// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Test Presale Floth Token
 * @author Ethereal Labs Ltd
 */

// ERC20 test contract for presale floth token
contract pFLOTHTest is ERC20, Ownable, ReentrancyGuard {

    // More readable and gas efficient way to write large numbers
    uint256 private constant DECIMALS = 18;
    uint256 private constant BILLION = 1_000_000_000;
    uint256 public MAX_SUPPLY = 30 * BILLION * 10**DECIMALS; // Can be modified for testing
    uint256 public WALLET_LIMIT = 25 * (BILLION / 10) * 10**DECIMALS; // 2.5 billion, can be modified
    uint256 public constant EXCHANGE_RATE = 10_000;
    uint256 public constant MIN_PURCHASE = 100_000_000 gwei; // 0.1 FLR

    // Pack variables together to save storage slots
     struct PresaleInfo {
        uint256 startTime;
        uint256 endTime;
        bool paused;
        bool finalized;
    }
    PresaleInfo public presaleInfo;

    // Mappings
    mapping(address => uint256) public pFLOTHBalance;

    /**
     * @dev Constructor initializes the contract with test parameters
     * @param _presaleDuration The duration of the presale in seconds
     */
    constructor(uint256 _presaleDuration) ERC20("Presale FlothTest", "pFLOTHTest") {
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

    // Errors
    error PresaleEnded();
    error ExceedsSupply();
    error TransferFailed();
    error PresaleNotStarted();
    error PresaleIsPaused();
    error BelowMinimumPurchase();
    error ExceedsWalletLimit();
    error InvalidRecoveryAmount();

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
        if (msg.value < MIN_PURCHASE) revert BelowMinimumPurchase();
        
        uint256 amountpFLOTH = msg.value * EXCHANGE_RATE;
        
        if (totalSupply() + amountpFLOTH > MAX_SUPPLY) revert ExceedsSupply();
        if (balanceOf(msg.sender) + amountpFLOTH > WALLET_LIMIT) revert ExceedsWalletLimit();

        _mint(msg.sender, amountpFLOTH);
        pFLOTHBalance[msg.sender] += amountpFLOTH;
        
        emit Presale(
            msg.sender,
            msg.value,
            amountpFLOTH,
            block.timestamp
        );
    }

    /**
     * @dev Test helper function to modify total supply
     * @param _supply New max supply value
     */
    function setTotalSupply(uint256 _supply) external onlyOwner {
        MAX_SUPPLY = _supply;
    }

    /**
     * @dev Test helper function to modify wallet limit
     * @param _limit New wallet limit value
     */
    function setWalletLimit(uint256 _limit) external onlyOwner {
        WALLET_LIMIT = _limit;
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
     * Emits a PresalePaused even
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
     * @dev Recover any ERC20 tokens accidentally sent to the contract
     * @param token The address of the token to recover
     * @param amount The amount of tokens to recover
     * Only the owner can call this function
     * Cannot be used to recover pFLOTH tokens
     * Implements nonReentrant pattern for security
     * Emits a TokenRecovered event upon successful recovery
     */
    function recoverERC20(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(this)) revert InvalidRecoveryAmount();
        if (amount > IERC20(token).balanceOf(address(this))) 
            revert InvalidRecoveryAmount();
        
        IERC20(token).transfer(owner(), amount);
        emit TokenRecovered(token, amount);
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
