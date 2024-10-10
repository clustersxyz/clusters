// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/EnumerableRoles.sol";

contract MockEnumerableRoles is EnumerableRoles {
    address public owner;

    uint256 public MAX_ROLE;

    function setOwner(address value) public {
        owner = value;
    }

    function setMaxRole(uint256 value) public {
        MAX_ROLE = value;
    }

    function thisOwner() public view returns (address) {
        return _thisOwner();
    }

    function maxRole() public view returns (uint256) {
        return _maxRole();
    }
}
