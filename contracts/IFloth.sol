// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFloth {
    function getPastVotes(
        address account,
        uint256 timepoint
    ) external view returns (uint256);

    function delegate(address delegatee) external;

    function balanceOf(address account) external view returns (uint256);

    function getGrantFundWallet() external view returns (address);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}
