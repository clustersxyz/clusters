// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";

/// @title EnumerableRoles
/// @notice Enumerable roles mixin that does not require inheritance from any specific ownable.
contract EnumerableRoles {
    using EnumerableSetLib for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The storage struct for the contract.
    struct EnumerableRolesStorage {
        // Mapping of `role` to a set of addresses with the role.
        mapping(uint8 => EnumerableSetLib.AddressSet) holders;
        // Mapping of an address to a set of roles it has.
        mapping(address => EnumerableSetLib.Uint8Set) roles;
    }

    /// @dev Returns the storage struct for the contract.
    function _getEnumerableRolesStorage() internal pure returns (EnumerableRolesStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.EnumerableRolesStorage")))`.
            $.slot := 0x214b1bb45059b2b86 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The status of `role` for `user` has been set to `active`.
    event RoleSet(address user, uint8 role, bool active);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Not authorized to set the role.
    error SetRoleUnauthorized();

    /// @dev Not authorized, as the caller does not have the role.
    error CheckRoleUnauthorized();

    /// @dev The role is greater than `MAX_ROLE`.
    error InvalidRole();

    /// @dev The user cannot be the zero address.
    error UserIsZeroAddress();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC WRITE FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the status of `role` for `user`.
    function setRole(address user, uint8 role, bool active) public payable virtual {
        if (msg.sender != _thisOwner()) revert SetRoleUnauthorized();
        _setRole(user, role, active);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns all the holders of `role`.
    function roleHolders(uint8 role) public view virtual returns (address[] memory) {
        return _getEnumerableRolesStorage().holders[role].values();
    }

    /// @dev Returns the number of holders with `role`.
    function roleHoldersCount(uint8 role) public view virtual returns (uint256) {
        return _getEnumerableRolesStorage().holders[role].length();
    }

    /// @dev Returns the holder of `role` at index `i`.
    function roleHoldersAt(uint8 role, uint256 i) public view virtual returns (address) {
        return _getEnumerableRolesStorage().holders[role].at(i);
    }

    /// @dev Returns the roles of `user`.
    function rolesOf(address user) public view virtual returns (uint8[] memory) {
        return _getEnumerableRolesStorage().roles[user].values();
    }

    /// @dev Returns if `user` has `role` set to active.
    function hasRole(address user, uint8 role) public view virtual returns (bool) {
        return _getEnumerableRolesStorage().roles[user].contains(role);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Guards a function such that the caller must have `role`.
    modifier onlyRole(uint8 role) virtual {
        _checkRole(role);
        _;
    }

    /// @dev Guards a function such that the caller must be the contact owner or have `role`.
    modifier onlyOwnerOrRole(uint8 role) virtual {
        _checkOwnerOrRole(role);
        _;
    }

    /// @dev Requires that the caller is the contract owner or has `role`.
    function _checkOwnerOrRole(uint8 role) internal virtual {
        if (msg.sender != _thisOwner()) {
            if (!hasRole(msg.sender, role)) revert CheckRoleUnauthorized();
        }
    }

    /// @dev Requires that the caller has `role`.
    function _checkRole(uint8 role) internal virtual {
        if (!hasRole(msg.sender, role)) revert CheckRoleUnauthorized();
    }

    /// @dev Sets the role without authorization checks.
    function _setRole(address user, uint8 role, bool active) internal virtual {
        if (role > _maxRole()) revert InvalidRole();
        if (user == address(0)) revert UserIsZeroAddress();
        EnumerableRolesStorage storage $ = _getEnumerableRolesStorage();
        if (active) {
            $.roles[user].add(role);
            $.holders[role].add(user);
        } else {
            $.roles[user].remove(role);
            $.holders[role].remove(user);
        }
        emit RoleSet(user, role, active);
    }

    /// @dev Returns the owner of the contract.
    function _thisOwner() internal view virtual returns (address result) {
        assembly ("memory-safe") {
            mstore(0x00, 0x8da5cb5b) // `owner()`.
            result :=
                mul(mload(0x00), and(gt(returndatasize(), 0x1f), staticcall(gas(), address(), 0x1c, 0x04, 0x00, 0x20)))
        }
    }

    /// @dev Returns the maximum valid role.
    function _maxRole() internal view virtual returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(0x00, 0xd24f19d5) // `MAX_ROLE()`.
            result :=
                mul(mload(0x00), and(gt(returndatasize(), 0x1f), staticcall(gas(), address(), 0x1c, 0x04, 0x00, 0x20)))
        }
    }
}
