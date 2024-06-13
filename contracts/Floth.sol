// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Floth is ERC20Votes, Ownable {
    //Bot tax in basis points (100 basis points = 1%)
    uint256 public buyTax = 2500; // 25%
    uint256 public sellTax = 3500; // 35%

    uint256 public deploymentTime;

    // Store DEX addresses to calculate if buy/sell/transfer.
    mapping(address => bool) public dexAddresses;

    address public grantFundWallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual wallet.
    address public lpPairAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; //Update to actual address.

    event SellTaxUpdate(uint256 newTax);
    event BuyTaxUpdate(uint256 newTax);
    event DexAddressAdded(address dexAddress);
    event DexAddressRemoved(address dexAddress);
    event GrantFundWalletUpdated(address newWallet);
    event LpPairAddressUpdated(address newAddress);

    error InvalidTaxAmount();
    error ZeroAddress();
    error SelfTransfer();

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
        if (_newSellTax > 500) {
            revert InvalidTaxAmount();
        }
        sellTax = _newSellTax;
        emit SellTaxUpdate(_newSellTax);
    }

    //Set buy bot tax.
    function setBuyBotTax(uint256 _newBuyTax) external onlyOwner {
        //Buy tax cannot be more than 5%.
        if (_newBuyTax > 500) {
            revert InvalidTaxAmount();
        }
        buyTax = _newBuyTax;
        emit BuyTaxUpdate(_newBuyTax);
    }

    //Add DEX address to mapping.
    function addDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert ZeroAddress();
        }

        dexAddresses[_dexAddress] = true;
        emit DexAddressAdded(_dexAddress);
    }

    //Remove DEX address from mapping.
    function removeDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert ZeroAddress();
        }

        dexAddresses[_dexAddress] = false;
        emit DexAddressRemoved(_dexAddress);
    }

    //Set grant fund wallet address.
    function setGrantFundWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) {
            revert ZeroAddress();
        }
        grantFundWallet = _newWallet;
        emit GrantFundWalletUpdated(_newWallet);
    }

    //Set LP Pair address.
    function setLpPairAddress(address _newAddress) external onlyOwner {
        if (_newAddress == address(0)) {
            revert ZeroAddress();
        }
        lpPairAddress = _newAddress;
        emit LpPairAddressUpdated(_newAddress);
    }

    //Transfer tokens with/without tax, based on buy/sell.
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override {
        if (_sender == _recipient || address(0) == _recipient) {
            revert SelfTransfer();
        }

        uint256 taxAmount = 0; // Amount to be taxed for this transaction.
        uint256 grantFundAmount = 0;
        uint256 lpPairingAmount = 0;

        if (dexAddresses[_sender]) {
            // Buy transaction
            taxAmount = (_amount * buyTax) / 10000; // Amount * buy tax in basis points.
            if (taxAmount > 0) {
                super._transfer(_sender, grantFundWallet, taxAmount);
            }
        } else if (dexAddresses[_recipient]) {
            // Sell transaction
            taxAmount = (_amount * sellTax) / 10000; // Amount * sell tax in basis points.
            if (taxAmount > 0) {
                grantFundAmount = (taxAmount * 833) / 1000; // 83.3% of tax amount (2.5% from the 3%)
                lpPairingAmount = taxAmount - grantFundAmount; // Remaining 16.7% of tax amount (0.5% from the 3%)
                super._transfer(_sender, grantFundWallet, grantFundAmount);
                super._transfer(_sender, lpPairAddress, lpPairingAmount);
                //Also send to the LP Pairing until 10% LP allocation reserve is depleted. REVIEW.
            }
        }

        uint256 totalPayable = _amount - taxAmount; // Final tax amount is deducted.
        super._transfer(_sender, _recipient, totalPayable);
    }
}
