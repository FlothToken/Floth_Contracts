// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Floth is ERC20Votes, Ownable {
    //Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    //Bot tax
    uint256 public buyTax = 25;
    uint256 public sellTax = 35;

    uint256 public deploymentTime;

    // Store DEX addresses to calculate if buy/sell/transfer.
    mapping(address => bool) public dexAddresses;

    address public grantFundWallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual wallet.
    address public lpPairAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual address.

    event SellTaxUpdate(uint256 newTax);
    event BuyTaxUpdate(uint256 newTax);
    event DexAddressAdded(address dexAddress);
    event DexAddressRemoved(address dexAddress);

    error InvalidTaxAmount();

    constructor(
        address[] memory _dexAddresses,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        _mint(msg.sender, 1000000 * 10 ** 18);
        deploymentTime = block.timestamp;

        for (uint256 i = 0; i < _dexAddresses.length; i++) {
            dexAddresses[_dexAddresses[i]] = true;
        }
    }

    //Set sell bot tax.
    function setSellBotTax(uint256 _newSellTax) external onlyOwner {
        //Sell tax cannot be more than 5%.
        if (_newSellTax > 5) {
            revert InvalidTaxAmount();
        }
        sellTax = _newSellTax;
        emit SellTaxUpdate(_newSellTax);
    }

    //Set buy bot tax.
    function setBuyBotTax(uint256 _newBuyTax) external onlyOwner {
        //Buy tax cannot be more than 5%.
        if (_newBuyTax > 5) {
            revert InvalidTaxAmount();
        }
        buyTax = _newBuyTax;
        emit BuyTaxUpdate(_newBuyTax);
    }

    //Add DEX address to mapping.
    function addDexAddress(address _dexAddress) external onlyOwner {
        dexAddresses[_dexAddress] = true;
        emit DexAddressAdded(_dexAddress);
    }

    //Remove DEX address to mapping.
    function removeDexAddress(address _dexAddress) external onlyOwner {
        dexAddresses[_dexAddress] = false;
        emit DexAddressRemoved(_dexAddress);
    }

    //Transfer tokens with/without tax, based on time of buy/sell.
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override {
        require(
            _recipient != address(this),
            "Contract sending tokens to itself is not allowed."
        );

        uint256 taxAmount = 0; //Amount to be taxed for this transaction.

        //Case for if it's a buy transaction.
        if (dexAddresses[_sender]) {
            taxAmount = _amount * (buyTax / 100); //Amount * buy tax as a decimal.
            if (taxAmount > 0) {
                super._transfer(_sender, grantFundWallet, taxAmount);
            }
        }
        //Case for if it's a sell transaction.
        if (dexAddresses[_recipient]) {
            taxAmount = _amount * (sellTax / 100); //Amount * sell tax as a decimal.

            if (taxAmount > 0) {
                uint256 grantFundAmount = (taxAmount * 833) / 1000; //83.3% (2.5% from the 3%)
                uint256 lpPairingAmount = taxAmount - grantFundAmount; //16.7% (0.5% from the 3%)
                super._transfer(_sender, grantFundWallet, grantFundAmount);
                //Also send to the LP Pairing until 10% LP allocation reserve is depleted. REVIEW.
            }
        }

        uint256 totalPayable = _amount - taxAmount; //Final tax amount is deducted.

        super._transfer(_sender, _recipient, totalPayable);
    }
}
