// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "./IFlothPassEvents.sol";

/**
 * @title IFlothPass - FlothPass contract interface
 * @author Ethereal Labs Ltd
 * @notice Interface for the FlothPass NFT functionality
 */
interface IFlothPass is IERC721Upgradeable, IFlothPassEvents {

    // Pack related storage variables together to save slots
    struct SaleConfig {
        uint16 numberMinted;
        uint16 maxSupply;           // 1000 NFTs
        uint16 maxWalletLimit;     // 25 NFTs
        bool saleActive;
    }

    // Pack price-related variables
    struct PriceConfig {
        uint128 usdStartPrice;
        uint128 usdPriceIncrement;
    }

    // Core functions
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getCurrentPriceInFlr(uint16 _quantity) external returns (uint256 totalPrice);
    function mint(uint16 _quantity) external payable;
    function withdrawTo(uint256 _amount, address _recipient, bool _withdrawAll) external;
    
    // State getters
    function getNumberMinted() external view returns (uint16);
    function getTokensMintedByAddress(address _address) external view returns (uint16);
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function isDelegated(address account, address accountDelegate) external view returns (bool);
    
    // Admin functions
    function setSaleActive(bool _saleActive) external;
    function setPriceIncrement(uint128 _newPriceIncrement) external;
    function setMaxSupply(uint16 _newMaxSupply) external;
    function setSymbol(string calldata _newSymbol) external;
    function setName(string calldata _newName) external;
    function setWithdrawAddress(address payable _withdrawAddress) external;
    function setBaseUri(string calldata _baseUri) external;
    function delegate(address delegatee) external;
} 