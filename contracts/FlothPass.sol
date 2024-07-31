// SPDX-License-Identifier: MIT  
/**                           
 * @title Floth Pass
 * @author Ethereal Labs
 * @notice Floth Pass - a contract for minting a FLOTH Pass
 */
pragma solidity ^0.8.11;

import "./IFloth.sol";
import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "erc721a-upgradeable/contracts/extensions/ERC721AQueryableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract FlothPass is
    ERC721AUpgradeable,
    ERC721AQueryableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    //Setup variables arranged for optimised storage slots

    //The address of the Floth contract
    IFloth public flothContract;

    //Payable withdraw address
    address payable public withdrawAddress;

    //Floth vault address
    address public flothVault;

    //The collection base URI
    string public _currentBaseURI;

    //Floth Initial Price
    uint256 public price; // 1000 FLOTH

    //Price increment
    uint256 public priceIncrement;

    //Mints since last increment
    uint16 public mintsSinceLastIncrement;

    //Max supply
    uint16 public maxSupply;

    //Public sale active flag
    bool public saleActive;

    /**
     * @dev To reduce smart contract size & gas usages, we are using custom errors rather than using require.
     */
    error SaleInactive();
    error InsufficientFunds();
    error InsufficientFundsInContract();
    error InsufficientRole();
    error ExceedsMaxSupply();
    error TransferFailed();
    error CannotMintToZeroAddress();

    //Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    ///////////////////////////////////////////////////////////////////////////
    // Initialize Functions
    ///////////////////////////////////////////////////////////////////////////

    /**
     * Initialize function for proxy.
     * Calls the internal initialize function.
     */
    function initialize() public initializerERC721A initializer {
        __ERC721A_init("Floth Pass", "FPASS");
        __ERC721AQueryable_init();
        __AccessControl_init();
        __FlothPass_init();

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(WITHDRAW_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * Initialize function which sets the defaults for state variables
     */
    function __FlothPass_init() internal initializer {
        _currentBaseURI = "";
        maxSupply = 333;
        price = 1000 ether;
        priceIncrement = 50 ether;
        flothVault = 0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739;
        withdrawAddress = payable(0xDF53617A8ba24239aBEAaF3913f456EbAbA8c739);
        flothContract = IFloth(0xa2EA5Cb0614f6428421a39ec09B013cC3336EFBe);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Mint Functions
    ///////////////////////////////////////////////////////////////////////////

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

        uint256 totalMinted = _totalMinted();

        // Check total minted against max supply
        if (totalMinted + _quantity > maxSupply) {
            revert ExceedsMaxSupply();
        }

        uint256 currentPrice = price;
        uint256 totalPrice = 0;

        // Calculate the total price considering the price increments every 10 mints
        // @dev Note i = 1 not i = 0
        for (uint16 i = 1; i <= _quantity; i++) {
            totalPrice += currentPrice;
            if ((totalMinted + i) % 10 == 0) {
                currentPrice += priceIncrement;
            }
        }

        // Check if the caller has enough FLOTH to cover the cost
        if (flothContract.balanceOf(msg.sender) < totalPrice) {
            revert InsufficientFunds();
        }

        // Transfer the total price from the caller to the flothVault
        flothContract.transferFrom(msg.sender, flothVault, totalPrice);

        // Mint the requested quantity to the caller
        _safeMint(msg.sender, _quantity);

        // Update the number of mints since the last price increment
        mintsSinceLastIncrement = (uint16(totalMinted) + _quantity) % 10;
        price = currentPrice; // Update the price to the new current price
    }


    ///////////////////////////////////////////////////////////////////////////
    // Withdraw Functions
    ///////////////////////////////////////////////////////////////////////////

    /**
     * @dev Withdraws the balance of the contract to the withdraw address if it exists.
     * If it does not exist, it withdraws to the caller.
     * Checks if caller has withdraw role or admin role.
     * Checks if withdraw address is valid.
     * @param _amount the amount to withdraw
     * @param _withdrawAll if true, withdraws the entire balance of the contract
     */
    function withdraw(
        uint256 _amount,
        bool _withdrawAll
    ) external nonReentrant {
        if (
            !hasRole(WITHDRAW_ROLE, msg.sender) &&
            !hasRole(ADMIN_ROLE, msg.sender)
        ) {
            revert InsufficientRole();
        }

        uint256 amountToWithdraw = _withdrawAll
            ? address(this).balance
            : _amount;

        // If _withdrawAll is false, then check if there are enough funds in the contract
        if (!_withdrawAll && amountToWithdraw > address(this).balance) {
            revert InsufficientFundsInContract();
        }

        address payable recipient = withdrawAddress != address(0)
            ? withdrawAddress
            : payable(msg.sender);

        _withdraw(recipient, amountToWithdraw);
    }

    /**
     * @dev Internal helper for withdrawing ether from the contract
     * @param _address the address to withdraw to
     * @param _amount the amount to withdraw
     */
    function _withdraw(address _address, uint256 _amount) internal {
        (bool success, ) = _address.call{value: _amount}("");
        if (!success){
            revert TransferFailed();
        }
    }

    /**
     * @dev Gets the number of floth passes minted for an owner.
     * @param _owner the owner of the floth passes to get the number minted for
     */
    function numberMinted(address _owner) public view returns (uint256) {
        return _numberMinted(_owner);
    }

    /**
     * @dev Function to obtain the uri/json file of a particular token id.
     * @param _tokenId the token id to get the uri for
     */
    function tokenURI(uint256 _tokenId) public view virtual override(ERC721AUpgradeable, IERC721AUpgradeable)   returns (string memory)
    {
        return super.tokenURI(_tokenId);
    }

    /**
     * @dev ERC721AUpgradeable internal function to set the starting token id.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @dev Used to identify the interfaces supported by this contract.
     * @param interfaceId the interface id to check for support
     */
    function supportsInterface(bytes4 interfaceId) public view override
    (ERC721AUpgradeable, IERC721AUpgradeable, AccessControlUpgradeable) returns (bool)
    {
        return ERC721AUpgradeable.supportsInterface(interfaceId) || 
               AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    ///////////////////////////////////////////////////////////////////////////
    //#region State Changes
    ///////////////////////////////////////////////////////////////////////////

    /**
     * @dev Sets the sale active state of the contract
     * @param _saleActive state to change to
     * Only callable by admin
     */
    function setSaleActive(bool _saleActive) external onlyRole(ADMIN_ROLE) {
        saleActive = _saleActive;
    }

    /**
     * @dev Sets the public mint price per floth pass
     * @param _newPrice the new public mint price
     * Only callable by admin
     */
    function setMintPrice(uint256 _newPrice) external onlyRole(ADMIN_ROLE) {
        price = _newPrice;
    }

    /**
     * @dev Sets the max supply of the floth pass
     * @param _newMaxSupply the new max supply
     * Only callable by admin
     */
    function setMaxSupply(uint16 _newMaxSupply) external onlyRole(ADMIN_ROLE){
        maxSupply = _newMaxSupply;
    }

    /**
     * @dev Sets the ticker symbol of the contract
     * @param _newSymbol the new ticker symbol
     * Only callable by admin
     */
    function setSymbol(
        string calldata _newSymbol
    ) external onlyRole(ADMIN_ROLE) {
        ERC721AStorage.layout()._symbol = _newSymbol;
    }

    /**
     * @dev Sets the name of the contract
     * @param _newName the new name of the contract
     * Only callable by admin
     */
    function setName(string calldata _newName) external onlyRole(ADMIN_ROLE) {
        ERC721AStorage.layout()._name = _newName;
    }

    /**
     * @dev Sets the withdrawal address of the contract
     * @param _withdrawAddress address to withdraw to
     * Only callable by admin
     */
    function setWithdrawAddress(
        address payable _withdrawAddress
    ) external onlyRole(ADMIN_ROLE) {
        withdrawAddress = _withdrawAddress;
    }

    /**
     * @dev Sets the floth contract address
     * @param _flothContractAddress address of the floth contract
     * Only callable by admin
     */
    function setFlothContract(
        address _flothContractAddress
    ) external onlyRole(ADMIN_ROLE) {
        flothContract = IFloth(_flothContractAddress);
    }

    /**
     * @dev Sets the base uri of the contract
     * @param _baseUri base uri to change to
     * Only callable by admin
     */
    function setBaseUri(
        string calldata _baseUri
    ) external onlyRole(ADMIN_ROLE) {
        _currentBaseURI = _baseUri;
    }

    /**
     * @dev Overrides the base uri function in ERC721A
     */
    function _baseURI() internal view override returns (string memory) {
        return _currentBaseURI;
    }
    //#endregion
}