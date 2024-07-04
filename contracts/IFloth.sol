// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFloth {
    function getPastVotes(
        address account,
        uint256 timepoint
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
