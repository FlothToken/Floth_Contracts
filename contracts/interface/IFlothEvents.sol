// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IBaseEvents.sol";

/**
 * @title IFlothEvents - Floth-specific events and errors interface
 * @author Ethereal Labs Ltd
 * @notice Events and errors specific to the Floth token contract
 */
interface IFlothEvents is IBaseEvents {
    // Floth-specific errors
    error InvalidTaxAmount();
    error InvalidTokenNameOrSymbol();

    // Floth-specific events
    event SellTaxUpdate(uint256 indexed newTax);
    event BuyTaxUpdate(uint256 indexed newTax);
    event DexAddressAdded(address indexed dexAddress);
    event DexAddressRemoved(address indexed dexAddress);
    event GrantFundWalletUpdated(address indexed newGrantFundWallet);
    event LpFundWalletUpdated(address indexed newLpFundWallet);
    event LpTaxUpdate(uint256 indexed newTax);
    event LpTaxStatusUpdate(bool indexed status);
    event LiquidityProviderUpdated(address indexed provider, bool indexed status);
} 