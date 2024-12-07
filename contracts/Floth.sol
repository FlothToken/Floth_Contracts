// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//TODO: On dex swap, swap FLOTH to Flare - take % and add to grant fund wallet.
/**
 * @title Floth ERC20 token on Flare.
 * @author Ethereal Labs Ltd
 */
contract Floth is ERC20Votes, Ownable, ReentrancyGuard {
    uint256 private constant INITIAL_SUPPLY = 100 * 10**9; // 100 billion
    uint256 private constant MAX_TAX = 500; // 5%
    uint256 private constant BASIS_POINTS = 10000;

    // Packing similar storage variables together to save slots
    struct TaxInfo {
        uint128 buyTax;  // Reduced to uint128 as it never exceeds this value
        uint128 sellTax; // Reduced to uint128 as it never exceeds this value
        uint128 lpTax; // Reduced to uint128 as it never exceeds this value
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
    event GrantFundWalletUpdated(address indexed newGrantFundWallet);
    event LpFundWalletUpdated(address indexed newLpFundWallet);
    event LpTaxUpdate(uint256 indexed newTax);
    event LiquidityProviderUpdated(address indexed provider, bool indexed status);
    // Custom errors save gas compared to require statements
    error InvalidTaxAmount();
    error ZeroAddress();
    error SelfTransfer();
    error InvalidTokenNameOrSymbol();
    error Paused();
    error ZeroAmount();
    error UnauthorizedLiquidityProvider();

    mapping(address => bool) public liquidityProviders;

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

        // Initialize tax structure 
        // Initially 25/35% for taxes but can only be changed to 5% after this initial period
        taxInfo.buyTax = 2500;  // 25%
        taxInfo.sellTax = 3500; // 35%
        taxInfo.lpTax = 500; // 0.5%
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
        if (amount == 0) revert ZeroAmount();
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
     * @dev Set LP tax with validation
     * @param _newLpTax New LP tax to be set.
     */
    function setLpTax(uint128 _newLpTax) external onlyOwner {
        //TODO: Do we have a max for this?
        taxInfo.lpTax = _newLpTax;
        emit LpTaxUpdate(_newLpTax);
    }

    /**
     * @dev Setter for grant fund wallet.
     * @param _newGrantFundWallet New grant fund wallet to be set.
     */
    function setGrantFundWallet(address _newGrantFundWallet) external onlyOwner {
        if (_newGrantFundWallet == address(0)) revert ZeroAddress();
        grantFundWallet = _newGrantFundWallet;
        emit GrantFundWalletUpdated(_newGrantFundWallet);
    }

    /**
     * @dev Setter for LP fund wallet.
     * @param _newLpFundWallet New LP fund wallet to be set.
     */
    function setLpFundWallet(address _newLpFundWallet) external onlyOwner {
        if (_newLpFundWallet == address(0)) revert ZeroAddress();
        lpFundWallet = _newLpFundWallet;
        emit LpFundWalletUpdated(_newLpFundWallet);
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
     * @return lpTax LP tax.
     * @return lpTaxActive LP tax active.
     * @return paused Paused.
     */
    function getTaxInfo() external view returns (
        uint128 buyTax,
        uint128 sellTax,
        uint128 lpTax,
        bool lpTaxActive,
        bool paused
    ) {
        return (
            taxInfo.buyTax,
            taxInfo.sellTax,
            taxInfo.lpTax,
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
     * @dev Set or remove liquidity provider status
     * @param _provider Address to update
     * @param _status New status
     */
    function setLiquidityProvider(address _provider, bool _status) external onlyOwner {
        if (_provider == address(0)) revert ZeroAddress();
        liquidityProviders[_provider] = _status;
        emit LiquidityProviderUpdated(_provider, _status);
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

        // Allow tax-free transfers for liquidity providers
        if (!dexAddresses[_sender] && !dexAddresses[_recipient] || liquidityProviders[_sender]) {
            super._transfer(_sender, _recipient, _amount);
            _handleDelegation(_recipient);
            return;
        }

        // Cache tax info in memory to save gas
        TaxInfo memory _taxInfo = taxInfo;

        uint256 taxAmount;
        uint256 lpTaxAmount;

        if (dexAddresses[_sender] && _taxInfo.buyTax > 0) {
            // Buy transaction
    
            //Calculate tax amount
            unchecked {
                taxAmount = (_amount * _taxInfo.buyTax) / BASIS_POINTS;
            }

            //Transfer tax amount to grant fund wallet
            super._transfer(_sender, grantFundWallet, taxAmount);

        } else if (dexAddresses[_recipient] && _taxInfo.sellTax > 0) {
            // Sell transaction

            //Calculate tax amount
            unchecked {
                taxAmount = (_amount * _taxInfo.sellTax) / BASIS_POINTS;
            }

            //Transfer tax amount to grant fund wallet
            super._transfer(_sender, grantFundWallet, taxAmount);

            //Transfer tax amount to LP fund wallet
            if (_taxInfo.lpTaxIsActive) {
                unchecked {
                    lpTaxAmount = (_amount * _taxInfo.lpTax) / BASIS_POINTS;
                }
                super._transfer(_sender, lpFundWallet, lpTaxAmount);
            }
        }

        //Transfer amount to recipient
        super._transfer(_sender, _recipient, _amount - taxAmount - lpTaxAmount);

        //Handle delegation
        _handleDelegation(_recipient);
    }

    /**
     * @dev Handle delegation logic
     * @param account Address of the account to handle delegation for.
     */
    function _handleDelegation(address account) private {
        _delegate(account, account);
    }
}
