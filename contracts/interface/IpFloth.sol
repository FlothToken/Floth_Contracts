// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBaseEvents.sol";

//TODO: Tidy up interface, errors, events, etc.
/**
 * @title IpFloth - Presale Floth token contract interface
 * @author Ethereal Labs Ltd
 * @notice Interface for the pFloth token functionality
 */
interface IpFloth is IERC20, IBaseEvents {

    // Pack variables together to save storage slots
    struct PresaleInfo {
        uint256 startTime;
        uint256 endTime;
        bool paused;
    }

    // pFloth-specific errors
    error PresaleEnded();
    error ExceedsSupply();
    error PresaleNotStarted();
    error PresaleIsPaused();
    error ExceedsWalletLimit();
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
    
    // View functions
    function pFLOTHPurchases(address account) external view returns (uint256);
    function tokenSenders(address token, address sender) external view returns (uint256);
    
    // Main functions
    function presale() external payable;
    function extendPresale(uint256 _additionalTime) external;
    function togglePresalePause() external;
    function withdraw() external;
    function recoverTokens(address _token, uint256 _amount) external;
    function returnTokens(address _token) external;
} 