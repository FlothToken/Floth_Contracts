// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IBaseEvents.sol";

/**
 * @title IpFlothEvents - pFloth-specific events and errors interface
 * @author Ethereal Labs Ltd
 * @notice Events and errors specific to the pFloth token contract
 */
interface IpFlothEvents is IBaseEvents {
    // pFloth-specific errors
    error PresaleEnded();
    error ExceedsSupply();
    error PresaleNotStarted();
    error PresaleIsPaused();
    error InvalidRecoveryToken();
    error InvalidRecoveryAmount();
    error UnauthorizedRecovery();

    // pFloth-specific events
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
} 