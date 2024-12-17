// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./FtsoV2Consumer.sol";


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
    
    // Pack related storage variables together to save slots
    struct SaleConfig {
        uint16 numberMinted;
        uint16 maxSupply;           // 1000 NFTs
        uint16 maxWalletLimit;     // 25 NFTs
        bool saleActive;
    }

    // Pack sale-related variables
    SaleConfig public saleConfig;

    // Pack price-related variables
    struct PriceConfig {
        uint128 usdStartPrice;
        uint128 usdPriceIncrement;
    }
    
    // Pack price-related variables
    PriceConfig public priceConfig;

    // Immutable roles for gas savings
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

     // Address to withdraw funds to.
    address payable public withdrawAddress;

    // Base URI for token metadata.
    string public _currentBaseURI;

    // Name and Symbol of the token
    string private _name;
    string private _symbol;

    // Mapping from address to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokens;
    mapping(uint256 => uint256) private _ownedTokensIndex; // tokenId => index in owner's array
    mapping(address => uint16) private _tokensMintedOnAddress;

    // Reference to FtsoV2Consumer contract
    FtsoV2Consumer public ftsoV2Consumer;

    // Gap for upgradeability
    uint256[50] private __gap;

    // Events
    event FallbackCalled(address indexed sender, uint256 value, bytes data);
    event PriceUpdated(uint256 newPrice);
    event BaseURIUpdated(string newUri);
    event TokensMinted(address indexed to, uint16 quantity, uint256 price);
    event NameUpdated(string newName);
    event SymbolUpdated(string newSymbol);

    // Custom errors for gas savings
    error SaleInactive();
    error InsufficientFunds();
    error InsufficientFundsInContract();
    error InsufficientRole();
    error ExceedsMaxSupply();
    error TransferFailed();
    error ZeroAddress();
    error InvalidPrice();
    error ExceedsWalletLimit();
    error InvalidMaxSupply();

    // Function to receive Ether. msg.data must be empty.
    receive() external payable {}

    // Fallback function is called when msg.data is not empty.
    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value, msg.data);
    }

    /**
     *
     * @dev Initialize function for proxy.
     * Calls the internal initialize function.
     */
    function initialize(address _ftsoV2ConsumerAddress) public initializer {
        if (_ftsoV2ConsumerAddress == address(0)) {
            revert ZeroAddress();
        }

        _name = "Floth Pass";
        _symbol = "FPASS";
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __ERC721Votes_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        // Initialize structs
        saleConfig = SaleConfig({
            numberMinted: 0,
            maxSupply: 1000,
            maxWalletLimit: 25,
            saleActive: false
        });

        priceConfig = PriceConfig({
            usdStartPrice: 50 ether,
            usdPriceIncrement: 50 ether
        });

        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(WITHDRAW_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Set reference to the deployed FtsoV2Consumer contract
        ftsoV2Consumer = FtsoV2Consumer(_ftsoV2ConsumerAddress);

        // Auto-delegate to self when initializing
        _delegate(msg.sender, msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Calculate current NFT price in FLR based on the dynamic FLR/USD price
     * @param _quantity The number of NFTs to mint
     * @return totalPrice Total price in FLR for all NFTs
     */
    function getCurrentPriceInFlr(uint16 _quantity) public returns (uint256 totalPrice) {
        uint256 currentMinted = saleConfig.numberMinted;
        uint256 totalUsdPrice = 0;
        
        // Calculate total USD price for all tokens
        for (uint16 i = 0; i < _quantity; i++) {
            uint256 incrementCount = (currentMinted + i) / 50;
            totalUsdPrice += priceConfig.usdStartPrice + (incrementCount * priceConfig.usdPriceIncrement);
        }
        
        // Single FTSO call for the total USD amount
        return ftsoV2Consumer.getDynamicPrice(totalUsdPrice);
    }


    /**
     * @dev Mint function to mint floth pass to the caller.
     * Requires the caller to have enough FLOTH to mint.
     * Requires the sale to be active.
     * Requires the total minted to be less than the max supply.
     * Requires the total minted plus the quantity to be less than the max supply.
     * @param _quantity the number of floth pass to mint
     */
    function mint(uint16 _quantity) external payable nonReentrant {
        if (!saleConfig.saleActive) {
            revert SaleInactive();
        }

        if (_tokensMintedOnAddress[msg.sender] + _quantity > saleConfig.maxWalletLimit) {
            revert ExceedsWalletLimit();
        }

        if (saleConfig.numberMinted + _quantity > saleConfig.maxSupply) {
            revert ExceedsMaxSupply();
        }

        uint256 totalPrice = getCurrentPriceInFlr(_quantity);

        // Check if the caller sent enough Flare to cover the cost
        if (msg.value < totalPrice) {
            revert InsufficientFunds();
        }

        // Batch mint tokens
        uint16 startTokenId = saleConfig.numberMinted;
        unchecked {
            for (uint16 i = 1; i <= _quantity; i++) {
                _safeMint(msg.sender, startTokenId + i);
            }
            saleConfig.numberMinted += _quantity;
            _tokensMintedOnAddress[msg.sender] += _quantity;
        }

        // Auto-delegate to self after minting
        if (!isDelegated(msg.sender, msg.sender)) {
            _delegate(msg.sender, msg.sender);
        }

        emit TokensMinted(msg.sender, _quantity, totalPrice);
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

        uint256 balance = address(this).balance;
        uint256 amountToWithdraw = _withdrawAll ? balance : _amount;
        
        if (!_withdrawAll && amountToWithdraw > balance) {
            revert InsufficientFundsInContract();
        }

        address payable recipient = withdrawAddress != address(0) ? withdrawAddress : payable(msg.sender);

        (bool success, ) = recipient.call{value: amountToWithdraw}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev Override for the tokenURI function to return the token URI
     * @param _tokenId the token id to get the URI for
     * @return tokenURI the token URI
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
        return saleConfig.numberMinted;
    }

    /**
     * @dev Getter for the number of tokens minted by an address
     * @param _address the address to get the number of tokens minted for
     * @return the number of tokens minted by the address
     */
    function getTokensMintedByAddress(address _address) external view returns (uint16) {
        return _tokensMintedOnAddress[_address];
    }

    /**
     * @dev Getter the owned tokens of an address
     * @param owner the address to get the owned tokens for
     * @return the owned tokens of the address
     */
    function tokensOfOwner(address owner) public view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    /**
     * @dev Setter for the sale active status
     * @param _saleActive the new sale active status
     */
    function setSaleActive(bool _saleActive) external onlyRole(ADMIN_ROLE) {
        saleConfig.saleActive = _saleActive;
    }

    /**
     * @dev Setter for the price to mint a token
     * @param _newPrice the new price to mint a token
     */
    // function setMintPrice(uint256 _newPrice) external onlyRole(ADMIN_ROLE) {
    //     price = _newPrice;
    // }

    /**
     * @dev Setter for the price increment
     * @param _newPriceIncrement the new price increment
     */
    function setPriceIncrement(uint128 _newPriceIncrement) external onlyRole(ADMIN_ROLE) {
        priceConfig.usdPriceIncrement = _newPriceIncrement;
    }

    /**
     * @dev Setter for the max supply of tokens
     * @param _newMaxSupply the new max supply of tokens
     */
    function setMaxSupply(uint16 _newMaxSupply) external onlyRole(ADMIN_ROLE) {
        if(_newMaxSupply < saleConfig.numberMinted) revert InvalidMaxSupply();
        if(_newMaxSupply > saleConfig.maxSupply) revert InvalidMaxSupply();
        saleConfig.maxSupply = _newMaxSupply;
    }

   /**
     * @dev Setter for the contract symbol
     * @param _newSymbol the new symbol for the contract
     */
    function setSymbol(string calldata _newSymbol) external onlyRole(ADMIN_ROLE) {
        _symbol = _newSymbol;
        emit SymbolUpdated(_newSymbol);
    }

    /**
     * @dev Setter for the contract name
     * @param _newName the new name for the contract
     */
    function setName(string calldata _newName) external onlyRole(ADMIN_ROLE) {
        _name = _newName;
        emit NameUpdated(_newName);
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
     * Updates the owner mappings for the token
     * @param from the address to transfer from
     * @param to the address to transfer to
     * @param tokenId the token id
     * @param batchSize the batch size
     */
    // Override _beforeTokenTransfer to track token ownership
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0)) {
            uint256[] storage tokens = _ownedTokens[from];
            uint256 lastTokenIndex = tokens.length - 1;
            uint256 tokenIndex = _ownedTokensIndex[tokenId];

            // If not the last token, swap positions
            if (tokenIndex != lastTokenIndex) {
                uint256 lastTokenId = tokens[lastTokenIndex];
                tokens[tokenIndex] = lastTokenId;
                _ownedTokensIndex[lastTokenId] = tokenIndex;
            }
            tokens.pop();
        }

        if (to != address(0)) {
            _ownedTokens[to].push(tokenId);
            _ownedTokensIndex[tokenId] = _ownedTokens[to].length - 1;
        }
    }

    /**
     * @dev Internal override for the after token transfer function
     * This is to ensure that all logic is called after a token is transferred
     * @param from the address to transfer from
     * @param to the address to transfer to
     * @param tokenId the token id
     * @param batchSize the batch size
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721VotesUpgradeable) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);

        // Auto-delegate for new owner if they haven't delegated before
        if (to != address(0) && !isDelegated(to, to)) {
            _delegate(to, to);
        }
    }

    // Helper function to check if address is already delegated
    function isDelegated(address account, address accountDelegate) public view returns (bool) {
        return delegates(account) == accountDelegate;
    }

    // Add explicit delegation function
    function delegate(address delegatee) public override {
        _delegate(_msgSender(), delegatee);
    }
}

