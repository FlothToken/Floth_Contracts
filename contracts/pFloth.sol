// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IpFloth.sol";
import {CommonValidators} from "./lib/CommonValidators.sol";


//TODO: Should not allow transfers only for purchases of FlothPass and exchanges to Floth.
//TODO: We need to track the burned amount.

/**
 * @title Presale Floth Token
 * @author Ethereal Labs
 */

// ERC20 contract for presale floth token
contract pFloth is ERC20, Ownable, ReentrancyGuard, IpFloth {

    // More readable and gas efficient way to write large numbers
    uint256 private constant DECIMALS = 18; //TODO: We can use decimals() from ERC20 contract here.
    uint256 private constant BILLION = 1_000_000_000;
    uint256 private constant _MAX_SUPPLY = 30 * BILLION * 10**DECIMALS;
    uint256 private constant _WALLET_LIMIT = 25 * (BILLION / 10) * 10**DECIMALS; // 2.5 billion
    uint256 private constant _EXCHANGE_RATE = 10_000;

    // Pack variables together to save storage slots
    //TODO: This can go in the interface.
    struct PresaleInfo {
        uint256 startTime;
        uint256 endTime;
        bool paused;
    }
    
    PresaleInfo public presaleInfo;

    // Mappings
    mapping(address => uint256) public pFLOTHPurchases;
    mapping(address => mapping(address => uint256)) public tokenSenders; // token => sender => amount

    /**
     * @dev Constructor for the pFloth contract
     * @param _presaleDuration The duration of the presale in seconds
     */
    constructor(uint256 _presaleDuration) ERC20("Presale Floth", "pFloth") {
        //TODO: Provide start and end time in constructor as unix timestamps.
        presaleInfo.startTime = block.timestamp;
        presaleInfo.endTime = block.timestamp + _presaleDuration;
        emit PresaleStarted(presaleInfo.startTime, presaleInfo.endTime);
    }

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
        
        uint256 amountpFLOTH = msg.value * _EXCHANGE_RATE;
        
        //TODO: Add param validators here
        if (totalSupply() + amountpFLOTH > _MAX_SUPPLY) revert ExceedsSupply();
        if (pFLOTHPurchases[msg.sender] + amountpFLOTH > _WALLET_LIMIT) revert ExceedsWalletLimit();
        
        pFLOTHPurchases[msg.sender] += amountpFLOTH;
        _mint(msg.sender, amountpFLOTH);

        emit Presale(
            msg.sender,
            msg.value,
            amountpFLOTH,
            block.timestamp
        );
    }
    
    //TODO: Change this to a setter for end time rather than extending.
    /**
     * @dev Function to extend the presale duration
     * @param _additionalTime The duration in seconds to extend the presale by
     * Only the owner can call this function
     */
    function extendPresale(uint256 _additionalTime) external onlyOwner {
        uint256 oldEndTime = presaleInfo.endTime;
        presaleInfo.endTime += _additionalTime;
        emit PresaleExtended(oldEndTime, presaleInfo.endTime);
    }

    /**
     * @dev Toggle emergency pause functionality
     * Only the owner can call this function
     * Emits a PresalePaused event
     */
    function togglePresalePause() external onlyOwner {
        presaleInfo.paused = !presaleInfo.paused;
        emit PresalePaused(presaleInfo.paused);
    }

    
    //TODO: Add an amount parameter to this function.
    //TODO: We may also want a recipient parameter.
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
     * @dev Function to recover ERC20 tokens
     * @param _token The token to recover
     * @param _amount The amount to recover
     */
    function recoverTokens(address _token, uint256 _amount) external onlyOwner nonReentrant {
        if (CommonValidators.isZeroAddress(_token)) revert InvalidRecoveryToken();
        if (CommonValidators.isZeroAmount(_amount)) revert InvalidRecoveryAmount();
        if (_token == address(this)) revert InvalidRecoveryToken();

        IERC20 token = IERC20(_token);
        bool success = token.transfer(owner(), _amount);
        if (!success) revert TransferFailed();

        emit TokenRecovered(_token, _amount);
    }

    /**
     * @dev Function to return tokens sent to contract
     * @param _token The token to return
     */
    function returnTokens(address _token) external nonReentrant {
        if (CommonValidators.isZeroAddress(_token)) revert InvalidRecoveryToken();
        if (_token == address(this)) revert InvalidRecoveryToken();
        if (tokenSenders[_token][msg.sender] == 0) revert UnauthorizedRecovery();

        IERC20 token = IERC20(_token);
        uint256 amount = tokenSenders[_token][msg.sender];
        tokenSenders[_token][msg.sender] = 0;
        
        bool success = token.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit TokenReturned(_token, msg.sender, amount);
    }

    /**
     * @dev Override for the _beforeTokenTransfer function
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param amount The amount of tokens being transferred
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            // Mint
            super._beforeTokenTransfer(from, to, amount);
        } else if (to == address(0)) {
            // Burn
            super._beforeTokenTransfer(from, to, amount);
        } else {
            // Transfer
            //TODO: Don't allow transfers unless for purchasing of FlothPass/Exchanging for Floth.
            super._beforeTokenTransfer(from, to, amount);
        }
    }

    /**
     * @dev Function that is called for all messages with data
     * @dev Stores tokens sent to the contract
     * @param _token The token address
     * @param _from The sender address
     * @param _value The value being sent
     * @dev _data parameter is not used in this implementation
     */
    function onERC20Received(address _token, address _from, uint256 _value, bytes calldata /*_data*/) external returns (bytes4) {
        if (CommonValidators.isZeroAddress(_token)) revert InvalidRecoveryToken();
        if (_token == address(this)) revert InvalidRecoveryToken();
        
        tokenSenders[_token][_from] += _value;
        
        return this.onERC20Received.selector;
    }

    /**
     * @dev Function to receive FLARE
     */
    receive() external payable {}

    /**
     * @dev View function to get remaining supply of pFLOTH tokens
     * @return uint256 The number of tokens still available for presale
     */
    function remainingSupply() external view returns (uint256) {
        return _MAX_SUPPLY - totalSupply();
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
        remaining = _MAX_SUPPLY - totalMinted;
        isActive = block.timestamp >= presaleInfo.startTime && 
                   block.timestamp <= presaleInfo.endTime && 
                   !presaleInfo.paused;
    }

    // Implement interface getter functions
    function MAX_SUPPLY() external pure override returns (uint256) {
        return _MAX_SUPPLY;
    }
    
    function WALLET_LIMIT() external pure override returns (uint256) {
        return _WALLET_LIMIT;
    }
    
    function EXCHANGE_RATE() external pure override returns (uint256) {
        return _EXCHANGE_RATE;
    }
}
