// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Utils {
    /// @dev Convert string to bytes32
    function _stringToBytes32(string memory name) internal pure returns (bytes32) {
        bytes memory stringBytes = bytes(name);
        return bytes32(stringBytes);
    }

    /// @dev Convert bytes32 to string
    function _bytes32ToString(bytes32 input) internal pure returns (string memory result) {
        if (input == bytes32("")) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, input)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, input)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }

    /// @dev Convert address to bytes32
    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @dev Convert bytes32 to address
    function _bytes32ToAddress(bytes32 input) internal pure returns (address) {
        return address(uint160(uint256(input)));
    }
}
