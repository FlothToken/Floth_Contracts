// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IFlothEvents.sol";

/**
 * @title IFloth - Floth token contract interface
 * @author Ethereal Labs Ltd
 * @notice Interface for the Floth token functionality
 */
interface IFloth is IERC20, IFlothEvents {
    // Struct definitions
    struct TaxInfo {
        uint256 buyTax;
        uint256 sellTax;
        uint256 lpTax;
        bool lpTaxIsActive;
        bool paused;
    }
    
    // View functions
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function grantFundWallet() external view returns (address);
    function getTaxInfo() external view returns (
        uint256 buyTax,
        uint256 sellTax, 
        uint256 lpTax,
        bool lpTaxActive,
        bool paused
    );
    function isDelegate(address account, address delegate) external view returns (bool);
    
    // Admin functions
    function setSellTax(uint256 _newSellTax) external;
    function setBuyTax(uint256 _newBuyTax) external;
    function setLpTax(uint256 _newLpTax) external;
    function setGrantFundWallet(address _newGrantFundWallet) external;
    function setLpFundWallet(address _newLpFundWallet) external;
    function togglePause() external;
    function addDexAddress(address _dexAddress) external;
    function removeDexAddress(address _dexAddress) external;
    function setLpTaxStatus(bool _status) external;
    function setLiquidityProvider(address _provider, bool _status) external;
} 