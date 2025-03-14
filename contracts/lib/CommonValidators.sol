// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title CommonValidators - Common validation functions
 * @author Ethereal Labs Ltd
 * @notice Library containing reusable validation functions
 */
library CommonValidators {
    /**
     * @dev Check if an address is the zero address
     * @param _address Address to check
     * @return True if the address is the zero address
     */
    function isZeroAddress(address _address) internal pure returns (bool) {
        return _address == address(0);
    }

    /**
     * @dev Check if an amount is zero
     * @param _amount Amount to check
     * @return True if the amount is zero
     */
    function isZeroAmount(uint256 _amount) internal pure returns (bool) {
        return _amount == 0;
    }

    /**
     * @dev Check if an amount exceeds a maximum value
     * @param _amount Amount to check
     * @param _maxAmount Maximum allowed amount
     * @return True if the amount exceeds the maximum
     */
    function exceedsMaximum(uint256 _amount, uint256 _maxAmount) internal pure returns (bool) {
        return _amount > _maxAmount;
    }

    /**
     * @dev Check if a string is empty
     * @param _str String to check
     * @return True if the string is empty
     */
    function isEmptyString(string memory _str) internal pure returns (bool) {
        return bytes(_str).length == 0;
    }

    /**
     * @dev Check if two addresses are the same
     * @param _address1 First address
     * @param _address2 Second address
     * @return True if the addresses are the same
     */
    function isSameAddress(address _address1, address _address2) internal pure returns (bool) {
        return _address1 == _address2;
    }
} 