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
} 