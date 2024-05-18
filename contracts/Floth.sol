// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract Floth is ERC20Votes {

    //Initial taxes for bots.
    uint256 public initialBuyTax = 25;
    uint256 public initialSellTax = 35;

    //Post-10 min taxes.
    uint256 public finalBuyTax = 0; 
    uint256 public finalSellTax = 3;

    //Bot tax time trackers.
    uint256 public taxPeriod = 10 minutes;
    uint256 public deploymentTime;

    //Tracks if transaction is a buy or a sell.
    bool private isBuy = false;
    bool private isSell = false;

    address public grantFundWallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual wallet.
    address public lpPairAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual address.

    constructor() ERC20("Floth", "FLOTH") {
        _mint(msg.sender, 1000000 * 10 ** 18);
        deploymentTime = block.timestamp;
    }

    //Gets the tax rates based on current time.
     function getTaxRates() public view returns (uint256 buyTax, uint256 sellTax) {
        //If less than 10 minutes have passed, use 25% buy / 35% sell tax.
        if (block.timestamp <= deploymentTime + taxPeriod) {
            return (initialBuyTax, initialSellTax);
        } else {
        //If 10 mins have passed, use normal tax rates.
            return (finalBuyTax, finalSellTax);
        }
    }

    //Transfer tokens with/without tax, based on time of buy/sell.
    function _transfer(address _from, address _to, uint256 _amount) internal override {
        require(_to != address(this), "BeamToken._transfer: transfer to self not allowed");

        uint256 taxAmount = 0; //Amount to be taxed for this transaction.
        (uint256 buyTax, uint256 sellTax) = getTaxRates(); //Get current tax rates.

        //Case for if it's a buy transaction.
        if(_from == address(this) && _to != address(0)){
            isBuy = true;
            taxAmount = _amount * (buyTax / 100); //Amount * buy tax as a decimal.
        }
        //Case for if it's a sell transaction.
        else if(_from != address(0) && _to == address(this)){
            isSell = true;
            taxAmount = _amount * (sellTax / 100); //Amount * sell tax as a decimal.
        }

        uint256 totalPayable = _amount - taxAmount; //Final tax amount is deducted.

        super._transfer(_from, _to, totalPayable);

        if (taxAmount > 0) {
            _distributeTax(_from, taxAmount);
        }
    }

    //Distributes the buy/sell tax.
    function _distributeTax(address _from, uint256 taxAmount) internal{
         if(isBuy){
            //Need to ask about what to do with 25% buy tax in initial 10 mins.
        }
        else if(isSell){
            uint256 grantFundAmount = taxAmount * (833 / 1000); //83.3% (2.5% from the 3%)
            uint256 lpPairingAmount = taxAmount - grantFundAmount; //16.3% (0.5% from the 3%)

            super._transfer(_from, grantFundWallet, grantFundAmount);
            
            //Also send to the LP Pairing until 10% LP allocation reserve is depleted.
        }
    }


}
