// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Floth ERC20 token on Flare.
 * @author Ethereal Labs
 */
contract Floth is ERC20Votes, Ownable {
    // Taxes in basis points (100 basis points = 1%)
    uint256 public buyTax = 2500; // 25%
    uint256 public sellTax = 3500; // 35%

    // LP tax status
    bool public lpTaxIsActive = true;

    // Store DEX addresses to calculate if buy/sell/transfer.
    mapping(address => bool) public dexAddresses;

    // FLOTH protocol wallets.
    address public grantFundWallet = 0x315c76C23e8815Fe0dFd8DD626782C49647924Ba; // TODO Update to actual wallet.
    address public lpFundWallet = 0x86d9c457969bd9Bb102D0876D959601aF681882D; // TODO Update to actual wallet.

    // Events
    event SellTaxUpdate(uint256 newTax);
    event BuyTaxUpdate(uint256 newTax);
    event DexAddressAdded(address dexAddress);
    event DexAddressRemoved(address dexAddress);
    event GrantFundWalletUpdated(address newWallet);
    event LpFundWalletUpdated(address newAddress);

    // Errors
    error InvalidTaxAmount();
    error ZeroAddress();
    error SelfTransfer();

    /**
     * Constructor to initialize the contract.
     * @param _dexAddresses Initial array of DEX addresses FLOTH is traded on
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     */
    constructor(
        address[] memory _dexAddresses,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        _mint(msg.sender, 100 * 10 ** 9 * 10 ** 18); // 100 billion tokens with 18 decimals.

        for (uint256 i = 0; i < _dexAddresses.length; i++) {
            dexAddresses[_dexAddresses[i]] = true;
        }
    }

    /**
     * @notice Set sell bot tax.
     * @param _newSellTax New sell tax in basis points.
     */
    function setSellTax(uint256 _newSellTax) external onlyOwner {
        // Sell tax cannot be more than 5%.
        if (_newSellTax > 500) {
            revert InvalidTaxAmount();
        }
        sellTax = _newSellTax;
        emit SellTaxUpdate(_newSellTax);
    }

    /**
     * @notice Set buy bot tax.
     * @param _newBuyTax New buy tax in basis points.
     */
    function setBuyTax(uint256 _newBuyTax) external onlyOwner {
        // Buy tax cannot be more than 5%.
        if (_newBuyTax > 500) {
            revert InvalidTaxAmount();
        }
        buyTax = _newBuyTax;
        emit BuyTaxUpdate(_newBuyTax);
    }

    /**
     * @notice Add DEX address to mapping.
     * @param _dexAddress Address of the DEX.
     */
    function addDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert ZeroAddress();
        }

        dexAddresses[_dexAddress] = true;
        emit DexAddressAdded(_dexAddress);
    }

    /**
     * @notice Remove DEX address from mapping.
     * @param _dexAddress Address of the DEX.
     */
    function removeDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) {
            revert ZeroAddress();
        }

        dexAddresses[_dexAddress] = false;
        emit DexAddressRemoved(_dexAddress);
    }

    /**
     * @notice Set grant fund wallet address.
     * @param _newWallet New grant fund wallet address.
     */
    function setGrantFundWallet(address _newWallet) external onlyOwner {
        if (_newWallet == address(0)) {
            revert ZeroAddress();
        }
        grantFundWallet = _newWallet;
        emit GrantFundWalletUpdated(_newWallet);
    }

    /**
     * @notice Set LP Pair address.
     * @param _newAddress New LP pair address.
     */
    function setLpFundWalletAddress(address _newAddress) external onlyOwner {
        if (_newAddress == address(0)) {
            revert ZeroAddress();
        }
        lpFundWallet = _newAddress;
        emit LpFundWalletUpdated(_newAddress);
    }

    /**
     * @notice Setter for LP Tax status.
     * @param _status New status for LP tax.
     */
    function setLpTaxStatus(bool _status) external onlyOwner {
        lpTaxIsActive = _status;
    }

    /**
     * @notice Transfer tokens with/without tax, based on buy/sell.
     * @param _sender Address of the sender.
     * @param _recipient Address of the recipient.
     * @param _amount Amount to be transferred.
     */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override {
        if (_sender == _recipient) {
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
                grantFundAmount = (taxAmount * 8333) / 10000; // 83.3% of tax amount (2.5% from the 3%)
                super._transfer(_sender, grantFundWallet, grantFundAmount);

                if (lpTaxIsActive) {
                    lpPairingAmount = taxAmount - grantFundAmount; // Remaining 16.7% of tax amount (0.5% from the 3%)
                    super._transfer(_sender, lpFundWallet, lpPairingAmount);
                }
            }
        }

        uint256 totalPayable = _amount - taxAmount; // Final tax amount is deducted.
        super._transfer(_sender, _recipient, totalPayable);
    }
}
