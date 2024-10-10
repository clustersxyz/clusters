// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {LibSort} from "solady/utils/LibSort.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import "./utils/SoladyTest.sol";
import "./mocks/MockEnumerableRoles.sol";

contract EnumerableRolesTest is SoladyTest {
    using DynamicArrayLib for *;

    MockEnumerableRoles internal enumerableRoles;

    function setUp() public {
        enumerableRoles = new MockEnumerableRoles();
    }

    function testSetAndGetMaxRole(uint256 value) public {
        enumerableRoles.setMaxRole(value);
        assertEq(enumerableRoles.maxRole(), value);
    }

    function testSetAndGetOwner(address value) public {
        enumerableRoles.setOwner(value);
        assertEq(enumerableRoles.thisOwner(), value);
    }

    function testSetAndGetRoles(bytes32) public {
        address user0;
        address user1;
        do {
            user0 = _randomNonZeroAddress();
            user1 = _randomNonZeroAddress();
        } while (user0 == address(0) || user1 == address(0) || user0 == user1);
        _testSetAndGetRoles(user0, user1, _sampleRoles(), _sampleRoles());
    }

    function testSetAndGetRoles() public {
        uint256[] memory allRoles = DynamicArrayLib.malloc(256);
        unchecked {
            for (uint256 i; i < 256; ++i) {
                allRoles.set(i, i);
            }
        }
        _testSetAndGetRoles(address(1), address(2), allRoles, allRoles);
    }

    function _testSetAndGetRoles(address user0, address user1, uint256[] memory user0Roles, uint256[] memory user1Roles)
        internal
    {
        enumerableRoles.setMaxRole(255);
        enumerableRoles.setOwner(address(this));
        unchecked {
            for (uint256 i; i != user0Roles.length; ++i) {
                enumerableRoles.setRole(user0, uint8(user0Roles.get(i)), true);
            }
            for (uint256 i; i != user1Roles.length; ++i) {
                enumerableRoles.setRole(user1, uint8(user1Roles.get(i)), true);
            }
            _checkRoles(user0, user0Roles);
            _checkRoles(user1, user1Roles);
            if (_randomChance(32)) {
                for (uint256 i; i < 256; ++i) {
                    if (!_randomChance(8)) continue;
                    uint8 role = uint8(i);
                    DynamicArrayLib.DynamicArray memory expected;
                    if (user0Roles.contains(role)) expected.p(user0);
                    if (user1Roles.contains(role)) expected.p(user1);
                    LibSort.sort(expected.data);
                    address[] memory roleHolders = enumerableRoles.roleHolders(role);
                    LibSort.sort(roleHolders);
                    assertEq(abi.encodePacked(expected.data), abi.encodePacked(roleHolders));
                }
            }
            for (uint256 i; i != user0Roles.length; ++i) {
                enumerableRoles.setRole(user0, uint8(user0Roles.get(i)), false);
            }
            for (uint256 i; i != user1Roles.length; ++i) {
                enumerableRoles.setRole(user1, uint8(user1Roles.get(i)), false);
            }
            assertEq(enumerableRoles.rolesOf(user0).length, 0);
            assertEq(enumerableRoles.rolesOf(user1).length, 0);
            if (_randomChance(32)) {
                for (uint256 i; i < 256; ++i) {
                    uint8 role = uint8(i);
                    assertEq(enumerableRoles.roleHolders(role).length, 0);
                }
            }
        }
    }

    function _checkRoles(address user, uint256[] memory sampledRoles) internal view {
        uint8[] memory roles = enumerableRoles.rolesOf(user);
        LibSort.sort(_toUint256Array(roles));
        sampledRoles = LibSort.copy(sampledRoles);
        LibSort.sort(sampledRoles);
        LibSort.uniquifySorted(sampledRoles);
        assertEq(_toUint256Array(roles), sampledRoles);
    }

    function _toUint256Array(uint8[] memory a) internal pure returns (uint256[] memory result) {
        assembly ("memory-safe") {
            result := a
        }
    }

    function _sampleRoles() internal returns (uint256[] memory roles) {
        unchecked {
            uint256 n = _random() & 0xf;
            roles = DynamicArrayLib.malloc(n);
            for (uint256 i; i != n; ++i) {
                roles.set(i, _random() & 0xff);
            }
        }
    }
}
