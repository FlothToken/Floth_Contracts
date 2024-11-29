// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Floth ERC20 token on Flare.
 * @author Ethereal Labs
 */
contract Floth is ERC20Votes, Ownable, ReentrancyGuard {
    uint256 private constant INITIAL_SUPPLY = 100 * 10**9; // 100 billion
    uint256 private constant MAX_TAX = 500; // 5%
    uint256 private constant BASIS_POINTS = 10000;

    uint256 private  GRANT_FUND_SPLIT = 8333; // 83.3% of tax amount (2.5% from the 3%)

    // Packing similar storage variables together to save slots
    struct TaxInfo {
        uint128 buyTax;  // Reduced to uint128 as it never exceeds this value
        uint128 sellTax; // Reduced to uint128 as it never exceeds this value
        bool lpTaxIsActive; // Flag to enable/disable LP tax
        bool paused; // Flag to enable/disable emergency pause
    }

    TaxInfo public taxInfo;

    // Store DEX addresses to calculate if buy/sell/transfer.
    mapping(address => bool) public dexAddresses;

     // FLOTH protocol wallets.
    address public grantFundWallet = 0x315c76C23e8815Fe0dFd8DD626782C49647924Ba; // TODO Update to actual wallet.
    address public lpFundWallet = 0x86d9c457969bd9Bb102D0876D959601aF681882D; // TODO Update to actual wallet.
    
    // Events - indexed important parameters for better filtering
    event SellTaxUpdate(uint256 indexed newTax);
    event BuyTaxUpdate(uint256 indexed newTax);
    event DexAddressAdded(address indexed dexAddress);
    event DexAddressRemoved(address indexed dexAddress);
    event EmergencyPause(bool indexed paused);

    // Custom errors save gas compared to require statements
    error InvalidTaxAmount();
    error ZeroAddress();
    error SelfTransfer();
    error InvalidTokenNameOrSymbol();
    error Paused();
    error InvalidAmount();

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
        if (bytes(_name).length == 0 || bytes(_symbol).length == 0) {
            revert InvalidTokenNameOrSymbol();
        }

        _mint(msg.sender, 100 * 10 ** 9 * 10 ** 18); // 100 billion tokens with 18 decimals.

        // Initialize tax structure 
        // Initially 25/35% for taxes but can only be changed to 5% after this initial period
        taxInfo.buyTax = 2500;  // 25%
        taxInfo.sellTax = 3500; // 35%
        taxInfo.lpTaxIsActive = true;
        taxInfo.paused = false;

        // Mint initial supply
        _mint(msg.sender, INITIAL_SUPPLY * 10**decimals());

        // Initialize DEX addresses
        unchecked {
            for (uint256 i = 0; i < _dexAddresses.length; i++) {
                dexAddresses[_dexAddresses[i]] = true;
            }
        }
    }

    /**
     * @dev Modifier to check if amount is valid
     * @param amount Amount to be checked.
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /**
     * @dev Emergency pause functionality modifier.
     */
    modifier whenNotPaused() {
        if (taxInfo.paused) revert Paused();
        _;
    }

    /**
     * @dev Set sell tax with validation
     * @param _newSellTax New sell tax to be set.
     */
    function setSellTax(uint128 _newSellTax) external onlyOwner {
        if (_newSellTax > MAX_TAX) revert InvalidTaxAmount();
        taxInfo.sellTax = _newSellTax;
        emit SellTaxUpdate(_newSellTax);
    }

    /**
     * @dev Set buy tax with validation
     * @param _newBuyTax New buy tax to be set.
     */
    function setBuyTax(uint128 _newBuyTax) external onlyOwner {
        if (_newBuyTax > MAX_TAX) revert InvalidTaxAmount();
        taxInfo.buyTax = _newBuyTax;
        emit BuyTaxUpdate(_newBuyTax);
    }

    /**
     * @dev Toggle emergency pause
     */
    function togglePause() external onlyOwner {
        taxInfo.paused = !taxInfo.paused;
        emit EmergencyPause(taxInfo.paused);
    }

    /**
     * @dev Batch read of tax information
     * @return buyTax Buy tax.  
     * @return sellTax Sell tax.
     * @return lpTaxActive LP tax active.
     * @return paused Paused.
     */
    function getTaxInfo() external view returns (
        uint128 buyTax,
        uint128 sellTax,
        bool lpTaxActive,
        bool paused
    ) {
        return (
            taxInfo.buyTax,
            taxInfo.sellTax,
            taxInfo.lpTaxIsActive,
            taxInfo.paused
        );
    }

    /**
     * @dev Add DEX address to mapping
     * @param _dexAddress Address to be added.
     */
    function addDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) revert ZeroAddress();
        dexAddresses[_dexAddress] = true;
        emit DexAddressAdded(_dexAddress);
    }

    /**
     * @dev Remove DEX address from mapping
     * @param _dexAddress Address to be removed.
     */
    function removeDexAddress(address _dexAddress) external onlyOwner {
        if (_dexAddress == address(0)) revert ZeroAddress();
        dexAddresses[_dexAddress] = false;
        emit DexAddressRemoved(_dexAddress);
    }

    /**
     * @dev Setter for LP Tax status.
     * @param _status New status for LP tax.
     */
    function setLpTaxStatus(bool _status) external onlyOwner {
        taxInfo.lpTaxIsActive = _status;
    }

    /**
     * @dev Transfer tokens with/without tax, based on buy/sell.
     * @param _sender Address of the sender.
     * @param _recipient Address of the recipient.
     * @param _amount Amount to be transferred.
     */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override whenNotPaused nonReentrant validAmount(_amount) {
        if (_sender == _recipient) revert SelfTransfer();

        // Cache tax info in memory to save gas
        TaxInfo memory _taxInfo = taxInfo;

        // Early return for non-taxed transfers
        if (!dexAddresses[_sender] && !dexAddresses[_recipient]) {
            super._transfer(_sender, _recipient, _amount);
            _handleDelegation(_recipient);
            return;
        }

        uint256 taxAmount;
        if (dexAddresses[_sender]) {
            // Buy transaction
            unchecked {
                taxAmount = (_amount * _taxInfo.buyTax) / BASIS_POINTS;
            }
            if (taxAmount > 0) {
                super._transfer(_sender, GRANT_FUND_WALLET, taxAmount);
            }
        } else {
            // Sell transaction
            unchecked {
                taxAmount = (_amount * _taxInfo.sellTax) / BASIS_POINTS;
            }
            if (taxAmount > 0) {
                uint256 grantFundAmount = (taxAmount * GRANT_FUND_SPLIT) / BASIS_POINTS;
                super._transfer(_sender, grantFundWallet, grantFundAmount);

                if (_taxInfo.lpTaxIsActive) {
                    super._transfer(_sender, lpFundWallet, taxAmount - grantFundAmount);
                }
            }
        }

        super._transfer(_sender, _recipient, _amount - taxAmount);
        _handleDelegation(_recipient);
    }

    /**
     * @dev Handle delegation logic
     */
    function _handleDelegation(address account) private {
        if (delegates(account) == address(0)) {
            _delegate(account, account);
        }
    }
}
