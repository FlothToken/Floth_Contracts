// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IpFloth.sol";
import {CommonValidators} from "../lib/CommonValidators.sol";

/**
 * @title Test Presale Floth Token
 * @author Ethereal Labs Ltd
 */

// ERC20 test contract for presale floth token
contract pFLOTHMock is ERC20, Ownable, ReentrancyGuard, IpFloth {

    // More readable and gas efficient way to write large numbers
    uint256 private constant BILLION = 1_000_000_000;
    //Removed as constant to allow for updates in testing version
    uint256 private MAX_SUPPLY = 30 * BILLION * 10**18;
    uint256 private WALLET_LIMIT = 25 * (BILLION / 10) * 10**18; // 2.5 billion
    uint256 private constant EXCHANGE_RATE = 10_000;

    // Track burned amount
    uint256 private _burnedAmount;

    // Authorized addresses that can receive pFLOTH transfers (e.g., FlothPass contract)
    mapping(address => bool) public authorizedReceivers;

    // Pack variables together to save storage slots
    PresaleInfo public presaleInfo;

    // Mappings
    mapping(address => uint256) public pFLOTHPurchases;
    mapping(address => mapping(address => uint256)) public tokenSenders; // token => sender => amount

    /**
     * @dev Constructor for the pFloth contract
     * @param _startTime The unix timestamp when the presale starts
     * @param _endTime The unix timestamp when the presale ends
     */
    constructor(uint256 _startTime, uint256 _endTime) ERC20("Presale Floth", "pFloth") {
        if (_startTime >= _endTime) revert InvalidPresaleTime();
        if (_startTime < block.timestamp) revert InvalidPresaleTime();
        
        presaleInfo.startTime = _startTime;
        presaleInfo.endTime = _endTime;
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
        // Validate parameters
        if (CommonValidators.isZeroAmount(msg.value)) revert InvalidAmount();
        
        uint256 amountpFLOTH = msg.value * EXCHANGE_RATE;
        
        if (totalSupply() + amountpFLOTH > MAX_SUPPLY) revert ExceedsSupply();
        if (pFLOTHPurchases[msg.sender] + amountpFLOTH > WALLET_LIMIT) revert ExceedsWalletLimit();
        
        pFLOTHPurchases[msg.sender] += amountpFLOTH;
        _mint(msg.sender, amountpFLOTH);

        emit Presale(
            msg.sender,
            msg.value,
            amountpFLOTH,
            block.timestamp
        );
    }

    /**
     * @dev Function to set the presale end time
     * @param _newEndTime The new end time for the presale (unix timestamp)
     * Only the owner can call this function
     */
    function setPresaleEndTime(uint256 _newEndTime) external onlyOwner {
        if (_newEndTime <= block.timestamp) revert InvalidPresaleTime();
        uint256 oldEndTime = presaleInfo.endTime;
        presaleInfo.endTime = _newEndTime;
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

        /**
     * @dev Extended function to withdraw FLR collected during the presale
     * @param _amount Amount to withdraw (0 for full balance)
     * @param _recipient Address to receive funds (default: owner)
     * Only the owner can call this function
     * Implements nonReentrant pattern for security
     * Emits a Withdraw event upon successful withdrawal
     */
    function withdrawTo(uint256 _amount, address _recipient, bool _withdrawAll) external onlyOwner nonReentrant {
        address recipient = _recipient == address(0) ? owner() : _recipient;
        uint256 withdrawAmount = _withdrawAll ? address(this).balance : _amount;
        
        if (withdrawAmount > address(this).balance) revert InsufficientBalance();
        
        (bool success, ) = recipient.call{value: withdrawAmount}("");
        if (!success) revert TransferFailed();

        emit WithdrawExecuted(recipient, withdrawAmount, _withdrawAll);
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
     * @dev Add or remove authorized receiver for pFLOTH transfers
     * @param _receiver The address to authorize/deauthorize
     * @param _authorized Whether the address is authorized
     */
    function setAuthorizedReceiver(address _receiver, bool _authorized) external onlyOwner {
        if (CommonValidators.isZeroAddress(_receiver)) revert ZeroAddress();
        authorizedReceivers[_receiver] = _authorized;
        emit AuthorizedReceiverUpdated(_receiver, _authorized);
    }

    /**
     * @dev Override for the _beforeTokenTransfer function
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param amount The amount of tokens being transferred
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            // Mint - allowed
            super._beforeTokenTransfer(from, to, amount);
        } else if (to == address(0)) {
            // Burn - track the amount
            _burnedAmount += amount;
            super._beforeTokenTransfer(from, to, amount);
        } else {
            // Transfer - only allow to authorized receivers
            if (!authorizedReceivers[to] && from != owner()) {
                revert UnauthorizedTransfer();
            }
            super._beforeTokenTransfer(from, to, amount);
        }
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
     * @return totalBurned The total amount of pFLOTH tokens burned
     * @return remaining The remaining amount of pFLOTH tokens available
     * @return isActive Whether the presale is currently active
     */
    function getPresaleStats() external view returns (
        uint256 totalRaised,
        uint256 totalMinted,
        uint256 totalBurned,
        uint256 remaining,
        bool isActive
    ) {
        totalRaised = address(this).balance;
        totalMinted = totalSupply();
        totalBurned = _burnedAmount;
        remaining = MAX_SUPPLY - totalMinted;
        isActive = block.timestamp >= presaleInfo.startTime && 
                   block.timestamp <= presaleInfo.endTime && 
                   !presaleInfo.paused;
    }

    /**
     * @dev Implements the interface function to get pFLOTH balance
     * @param account The address to check the balance of
     * @return uint256 The balance of pFLOTH for the account
     */
    function pFLOTHBalance(address account) external view override returns (uint256) {
        return pFLOTHPurchases[account];
    }
}
