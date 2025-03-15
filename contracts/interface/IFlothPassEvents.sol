// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IBaseEvents.sol";

/**
 * @title IFlothPassEvents - FlothPass-specific events and errors interface
 * @author Ethereal Labs Ltd
 * @notice Events and errors specific to the FlothPass NFT contract
 */
interface IFlothPassEvents is IBaseEvents {
    // FlothPass-specific errors
    error SaleInactive();
    error ExceedsMaxSupply();
    error InvalidMaxSupply();
    error InsufficientFundsInContract();
    error InvalidPrice();
    error UnauthorizedTransfer();
    error InvalidRecoveryToken();

    // FlothPass-specific events
    event FallbackCalled(address indexed sender, uint256 value, bytes data);
    event PriceUpdated(uint256 newPrice);
    event BaseURIUpdated(string newUri);
    event TokensMinted(address indexed to, uint16 quantity, uint256 price);
    event PriceIncrementUpdated(uint128 newIncrement);
    event MaxSupplyUpdated(uint16 newMaxSupply);
    event SaleStatusUpdated(bool isActive);
} 