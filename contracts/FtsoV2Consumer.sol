// SPDX-License-Identifier: MIT

pragma solidity >=0.8.2 <0.9.0;

import "@flarenetwork/flare-periphery-contracts/flare/ContractRegistry.sol";
import "@flarenetwork/flare-periphery-contracts/flare/FtsoV2Interface.sol";

interface IPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract FtsoV2Consumer {
    FtsoV2Interface internal ftsoV2;

    //Optional ftso address is for testing only to mock the ContractRegistry.
    constructor(address _ftsoV2Address) {
        if (_ftsoV2Address != address(0)) {
            // Use the provided address if it's not the zero address
            ftsoV2 = FtsoV2Interface(_ftsoV2Address);
        } else {
            // Otherwise, fall back to using ContractRegistry to get the FtsoV2
            ftsoV2 = ContractRegistry.getFtsoV2();
        }
    }

    function getFlrUsdPrice() public payable returns (uint256 value, int8 decimals, uint64 timestamp) {
        return ftsoV2.getFeedById{value: msg.value}(0x01464c522f55534400000000000000000000000000);
    }

    function getInputAmount(address pairAddress, address inputToken, uint256 outputAmount) public view returns (uint256 inputAmount) {
        IPair pair = IPair(pairAddress);
        
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
        uint256 inputReserve;
        uint256 outputReserve;
        
        if (pair.token0() == inputToken) {
            inputReserve = reserve0;
            outputReserve = reserve1;
        } else {
            require(pair.token1() == inputToken, "Input token not in pair");
            inputReserve = reserve1;
            outputReserve = reserve0;
        }
        
        require(outputReserve > outputAmount, "Insufficient liquidity");
        
        uint256 numerator = inputReserve * outputAmount * 1000;
        uint256 denominator = (outputReserve - outputAmount) * 997;
        inputAmount = (numerator / denominator) + 1;
    }

    function getDynamicPrice(uint256 usdAsk) external payable returns (uint256) {
        (uint256 value, int8 decimals,) = getFlrUsdPrice();
        uint256 amount = (usdAsk * 10 ** (18 + uint256(uint8(decimals)))) / value;
        return getInputAmount(0xAcf316C2177D166593096E4ba118320044fFc56a, 0x7F720688AC040Bf03Bc86aDeD8Ef4fdB3eA47f0f, amount);
    }
}