// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Each cluster has an ID
// The ID is the unique identifir
// The ID points to a set of addresses
// Address can only be in one cluster at a time
// Can a cluster have multiple names?
// What should we call an address within a cluster?

contract Clusters {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 nextClusterId = 1;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) public clusterLookup;

    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) public clusterMembers;

    mapping(uint256 clusterId => string name) public clusterNames;

    mapping(uint256 clusterId => mapping(address addr => bool invited)) invited;

    constructor() {}

    function invite(address invitee) external {
        uint256 currentCluster = clusterLookup[msg.sender];
        invited[currentCluster][invitee] = true;
    }

    function join(uint256 clusterId) external {
        require(invited[clusterId][invitee], "not invited");
        invited[clusterId][invitee] = false;
        clusterLookup[msg.sender] = clusterId;
        clusterMembers[clusterId].add(msg.sender);
    }
}
