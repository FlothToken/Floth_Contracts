// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Floth Interface
 * @author Ethereal Labs Ltd
 */
interface IFloth {
    // Core ERC20 & voting functionality
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function delegate(address delegatee) external;

    function balanceOf(address account) external view returns (uint256);

    function grantFundWallet() external view returns (address);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    function getTaxInfo() external view returns (
        uint256 buyTax,
        uint256 sellTax,
        uint256 lpTax,
        bool lpTaxActive,
        bool paused
    );
    
    // Public view functions for addresses
    function dexAddresses(address) external view returns (bool);
    function lpFundWallet() external view returns (address);
}
