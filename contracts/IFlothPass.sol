// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFlothPass {
    function balanceOf(address account) external view returns (uint256);

    function getNumberMinted() external view returns (uint16);

    function ownerOf(uint256 tokenId) external view returns (address);
}
