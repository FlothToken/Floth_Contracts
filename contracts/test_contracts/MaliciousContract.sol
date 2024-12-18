// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Floth.sol";

contract MaliciousContract {
    Floth public floth;
    
    constructor(address _floth) {
        floth = Floth(_floth);
    }
    
    function attack() external {
        floth.transfer(address(this), 100);
    }
    
    function onERC20Received(address, uint256) external returns (bytes4) {
        // Try to make a reentrant call
        floth.transfer(msg.sender, 50);
        return this.onERC20Received.selector;
    }
}