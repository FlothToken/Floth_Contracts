// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract Floth is ERC20Votes {
    constructor() ERC20("Floth", "FLOTH") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        require(
            _to != address(this),
            "BeamToken._transfer: transfer to self not allowed"
        );
        super._transfer(_from, _to, _amount);
    }
}
