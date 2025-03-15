// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IBaseEvents - Base events and errors interface
 * @author Ethereal Labs Ltd
 * @notice Common events and errors used across the Floth ecosystem
 */
interface IBaseEvents {
    // Common errors
    error ZeroAddress();
    error ZeroAmount();
    error Paused();
    error InsufficientFunds();
    error InsufficientRole();
    error TransferFailed();
    error ExceedsWalletLimit();
    error InvalidAmount();
    error InsufficientBalance();
    
    // Common events
    event EmergencyPause(bool indexed paused);
    event NameUpdated(string newName);
    event SymbolUpdated(string newSymbol);
    
    /**
     * @dev Emitted when tokens are transferred between addresses
     * @param tokenId The ID of the token being transferred
     * @param from The address the token is being transferred from
     * @param to The address the token is being transferred to
     */
    event TokenTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    
    /**
     * @dev Emitted when funds are withdrawn from a contract
     * @param to The address receiving the withdrawn funds
     * @param amount The amount being withdrawn
     * @param wasFullWithdraw Whether this was a full withdrawal of contract balance
     */
    event WithdrawExecuted(address indexed to, uint256 amount, bool wasFullWithdraw);
} 