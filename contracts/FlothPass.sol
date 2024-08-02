// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IFloth.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "hardhat/console.sol";

/**
 * @title FlothPass contract for minting Floth Pass NFTs.
 * @author Ethereal Labs Ltd
 * @notice This contract allows users to mint Floth Pass NFTs using FLOTH tokens.
 */
contract FlothPass is
    ERC721VotesUpgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Floth contract interface.
    IFloth public flothContract;

    // Address to withdraw funds to.
    address payable public withdrawAddress;

    // Address to send minted FLOTH to.
    address public flothVault;

    // Base URI for token metadata.
    string public _currentBaseURI;

    // Price to mint a single token.
    uint256 public price;

    // Price increment for every 10 tokens minted.
    uint256 public priceIncrement;

    // Number of tokens minted.
    uint16 public numberMinted;

    // Number of mints since last price increment.
    uint16 public mintsSinceLastIncrement;

    // Maximum number of tokens that can be minted.
    uint16 public maxSupply;

    // Whether the sale is active.
    bool public saleActive;

    // Custom name and symbol storage
    string private _name;
    string private _symbol;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    // Gap for upgradeability
    uint256[50] private __gap;

    // Events
    error SaleInactive();
    error InsufficientFunds();
    error InsufficientFundsInContract();
    error InsufficientRole();
    error ExceedsMaxSupply();
    error TransferFailed();
    error ZeroAddress();

    /**
     *
     * @dev Initialize function for proxy.
     * Calls the internal initialize function.
     * @param flothContractAddress Address of the Floth contract.
     */
    function initialize(address flothContractAddress) public initializer {
        __ERC721_init("Floth Pass", "FPASS");
        __ERC721Enumerable_init();
        __ERC721Votes_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __FlothPass_init(flothContractAddress);

        _name = "Floth Pass";
        _symbol = "FPASS";


        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(WITHDRAW_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Initialize function which sets the defaults for state variables
     * @param flothContractAddress Address of the Floth contract.
     */
    function __FlothPass_init(address flothContractAddress) internal initializer {
        _currentBaseURI = "";
        maxSupply = 333;
        price = 1000 ether;
        priceIncrement = 50 ether;
        flothVault = 0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739;
        withdrawAddress = payable(0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739);
        flothContract = IFloth(flothContractAddress);
    }

    /**
     * @dev Constructor prevents the contract from being initialized again
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Mint function to mint floth pass to the caller.
     * Requires the caller to have enough FLOTH to mint.
     * Requires the sale to be active.
     * Requires the total minted to be less than the max supply.
     * Requires the total minted plus the quantity to be less than the max supply.
     * @param _quantity the number of floth pass to mint
     */
    function mint(uint16 _quantity) external {
        if (!saleActive) {
            revert SaleInactive();
        }

        // Check if the total minted plus the quantity is less than the max supply.
        if (numberMinted + _quantity > maxSupply) {
            revert ExceedsMaxSupply();
        }

        uint256 currentPrice = price;
        uint256 totalPrice = 0;

        // Calculate the total price considering the price increments every 10 mints
        // @dev Note i = 1 not i = 0
        for (uint16 i = 1; i <= _quantity; i++) {
            totalPrice += currentPrice;
            if ((numberMinted + i) % 10 == 0) {
                currentPrice += priceIncrement;
            }
        }

        // Check if the caller has enough FLOTH to cover the cost
        if (flothContract.balanceOf(msg.sender) < totalPrice) {
            revert InsufficientFunds();
        }

        // Transfer the total price from the caller to the flothVault
        flothContract.transferFrom(msg.sender, flothVault, totalPrice);

        // Mint the quantity of tokens to the caller
        for (uint16 i = 0; i < _quantity; i++) {
            _safeMint(msg.sender, numberMinted += 1);
        }

        mintsSinceLastIncrement = (numberMinted + _quantity) % 10;

        // Update the price to the new current price
        price = currentPrice;
    }
    
    /**
     * @dev Withdraw function to withdraw flare funds from the contract.
     * Requires the caller to have the WITHDRAW_ROLE or ADMIN_ROLE.
     * @param _amount the amount to withdraw
     * @param _withdrawAll whether to withdraw all the funds
     */
    function withdraw(uint256 _amount, bool _withdrawAll) external nonReentrant {
        if (!hasRole(WITHDRAW_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert InsufficientRole();
        }

        uint256 amountToWithdraw = _withdrawAll ? address(this).balance : _amount;
        if (!_withdrawAll && amountToWithdraw > address(this).balance) {
            revert InsufficientFundsInContract();
        }

        address payable recipient = withdrawAddress != address(0) ? withdrawAddress : payable(msg.sender);
        _withdraw(recipient, amountToWithdraw);
    }

    /**
     * @dev Internal helper for withdrawing ether from the contract
     * @param _address the address to withdraw to
     * @param _amount the amount to withdraw
     */
    function _withdraw(address _address, uint256 _amount) internal {
        (bool success, ) = _address.call{value: _amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev Withdraw FLOTH function to withdraw FLOTH from the contract.
     * @param _amount the amount to withdraw
     * @param _withdrawAll whether to withdraw all the funds
     */
    function withdrawFLOTH(uint256 _amount, bool _withdrawAll) external nonReentrant {
        if (!hasRole(WITHDRAW_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert InsufficientRole();
        }

        uint256 amountToWithdraw = _withdrawAll ? flothContract.balanceOf(address(this)) : _amount;
        if (!_withdrawAll && amountToWithdraw > flothContract.balanceOf(address(this))) {
            revert InsufficientFundsInContract();
        }

        address recipient = withdrawAddress != address(0) ? withdrawAddress : msg.sender;
        flothContract.transfer(recipient, amountToWithdraw);
    }

    /**
     * @dev Override for the tokenURI function to return the token URI
     * @param _tokenId the token id to get the URI for
     * @return the token URI
     */
    function tokenURI(uint256 _tokenId) public view override(ERC721Upgradeable) returns (string memory) {
        return super.tokenURI(_tokenId);
    }

    /**
     * @dev Override for the supportsInterface function to return the supported interfaces
     * @param interfaceId the interface id to check
     * @return whether the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
        return ERC721EnumerableUpgradeable.supportsInterface(interfaceId) || AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev Getter for the number of tokens minted
     * @return the number of tokens minted
     */
    function getNumberMinted() external view returns (uint16) {
        return numberMinted;
    }

    /**
     * @dev Setter for the sale active status
     * @param _saleActive the new sale active status
     */
    function setSaleActive(bool _saleActive) external onlyRole(ADMIN_ROLE) {
        saleActive = _saleActive;
    }

    /**
     * @dev Setter for the price to mint a token
     * @param _newPrice the new price to mint a token
     */
    function setMintPrice(uint256 _newPrice) external onlyRole(ADMIN_ROLE) {
        price = _newPrice;
    }

    /**
     * @dev Setter for the max supply of tokens
     * @param _newMaxSupply the new max supply of tokens
     */
    function setMaxSupply(uint16 _newMaxSupply) external onlyRole(ADMIN_ROLE) {
        maxSupply = _newMaxSupply;
    }

   /**
     * @dev Setter for the contract symbol
     * @param _newSymbol the new symbol for the contract
     */
    function setSymbol(string calldata _newSymbol) external onlyRole(ADMIN_ROLE) {
        _symbol = _newSymbol;
    }

    /**
     * @dev Setter for the contract name
     * @param _newName the new name for the contract
     */
    function setName(string calldata _newName) external onlyRole(ADMIN_ROLE) {
        _name = _newName;
    }

    /**
     * @dev Setter for the withdraw address
     * @param _withdrawAddress the new withdraw address
     */
    function setWithdrawAddress(address payable _withdrawAddress) external onlyRole(ADMIN_ROLE) {
        if(_withdrawAddress == address(0)){
            revert ZeroAddress();
        }
        withdrawAddress = _withdrawAddress;
    }

    /**
     * @dev Setter for the floth contract address
     * @param _flothContractAddress the new floth contract address
     */
    function setFlothContract(address _flothContractAddress) external onlyRole(ADMIN_ROLE) {
        if(_flothContractAddress == address(0)){
            revert ZeroAddress();
        }
        flothContract = IFloth(_flothContractAddress);
    }

    /**
     * @dev Setter for the base uri
     * @param _baseUri the new base uri
     */
    function setBaseUri(string calldata _baseUri) external onlyRole(ADMIN_ROLE) {
        _currentBaseURI = _baseUri;
    }

    /**
     * @dev Internal function to get the base URI
     * @return the base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _currentBaseURI;
    }


    /**
     * @dev Getter for the contract symbol
     * @return the symbol of the contract
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Getter for the contract name
     * @return the name of the contract
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Internal override for the before token transfer function
     * This is to ensure that all logic is called before a token is transferred
     * @param from the address to transfer from
     * @param to the address to transfer to
     * @param tokenId the token id
     * @param batchSize the batch size
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Internal override for the after token transfer function
     * This is to ensure that all logic is called after a token is transferred
     * @param from the address to transfer from
     * @param to the address to transfer to
     * @param tokenId the token id
     * @param batchSize the batch size
     */
    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721Upgradeable, ERC721VotesUpgradeable) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
    }
}
