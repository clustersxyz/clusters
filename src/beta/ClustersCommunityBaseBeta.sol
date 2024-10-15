// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";

contract ClustersCommunityBaseBeta is EnumerableRoles, UUPSUpgradeable {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Admin role.
    uint256 public constant ADMIN_ROLE = 0;

    /// @dev Withdrawer role.
    uint256 public constant WITHDRAWER_ROLE = 1;

    /// @dev Max role.
    uint256 public constant MAX_ROLE = 1;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     WITHDRAW FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner to withdraw ERC20 tokens.
    function withdrawERC20(address token, address to, uint256 amount)
        public
        onlyOwnerOrRoles(abi.encode(ADMIN_ROLE, WITHDRAWER_ROLE))
    {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @dev Allows the owner to withdraw native currency.
    function withdrawNative(address to, uint256 amount)
        public
        onlyOwnerOrRoles(abi.encode(ADMIN_ROLE, WITHDRAWER_ROLE))
    {
        SafeTransferLib.safeTransferETH(to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns `a[i]`, without bounds checking.
    function _get(address[] calldata a, uint256 i) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := calldataload(add(a.offset, shl(5, i)))
        }
    }

    /// @dev Returns `a[i]`, without bounds checking.
    function _get(uint256[] calldata a, uint256 i) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            result := calldataload(add(a.offset, shl(5, i)))
        }
    }

    /// @dev Returns `a[i]`, without bounds checking.
    function _get(bytes32[] calldata a, uint256 i) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := calldataload(add(a.offset, shl(5, i)))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allow admins to set roles too.
    function _authorizeSetRole(address, uint256, bool) internal override onlyOwnerOrRoles(abi.encode(ADMIN_ROLE)) {}

    /// @dev For UUPSUpgradeable. Only the owner can upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwnerOrRoles(abi.encode(ADMIN_ROLE)) {}
}
