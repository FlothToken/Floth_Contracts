// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract FtsoV2ConsumerMock {

    constructor(address _ftsoV2Address) {
        // Constructor logic removed as it's not needed for the mock
    }

    function getFlrUsdPrice() public payable returns (uint256 /*value*/, int8 /*decimals*/, uint64 /*timestamp*/) {
        // Hardcoded return values
        return (50000000000000000000, 18, 1234567890);
    }

    function getInputAmount(address /*pairAddress*/, address /*inputToken*/, uint256 /*outputAmount*/) public view returns (uint256 inputAmount) {
        // Hardcoded return value
        return 1000000000000000000; // 1 FLR
    }

    function getDynamicPrice(uint256 /*usdAsk*/) external payable returns (uint256) {
        // Hardcoded return value
        return 2000000000000000000; // 2 FLR
    }

    function getCurrentPriceInFlr() external pure returns (uint256) {
        return 2000000000000000000; // 2 FLR
    }
}

