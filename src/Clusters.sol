// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {NameManager} from "./NameManager.sol";

import {IClusters} from "./IClusters.sol";

/**
 * OPEN QUESTIONS/TODOS
 * Can you create a cluster without registering a name? No, there needs to be a bounty for adding others to your cluster
 * What does the empty foobar/ resolver point to?
 */

contract Clusters is NameManager {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    constructor(address _pricing, address _endpoint) NameManager(_pricing, _endpoint) {}

    /// @dev For payable multicall to be secure, we cannot trust msg.value params in other external methods
    /// @dev Must instead do strict protocol invariant checking at the end of methods like Uniswap V2
    function multicall(bytes[] calldata _data) external payable returns (bytes[] memory results) {
        results = new bytes[](_data.length);
        bool success;
        unchecked {
            for (uint256 i = 0; i < _data.length; ++i) {
                //slither-disable-next-line calls-loop,delegatecall-loop
                (success, results[i]) = address(this).delegatecall(_data[i]);
                if (!success) revert MulticallFailed();
            }
        }
    }

    /// PUBLIC FUNCTIONS ///

    function create() external {
        create(msg.sender);
    }

    function create(address msgSender) public onlyEndpoint(msgSender) {
        _add(msgSender, nextClusterId++);
    }

    function add(address addr) external checkPrivileges("") {
        add(msg.sender, addr);
    }

    function add(address msgSender, address addr) public onlyEndpoint(msgSender) {
        _checkZeroCluster(msgSender);
        if (addressLookup[addr] != 0) revert Registered();
        _add(addr, addressLookup[msgSender]);
    }

    function remove(address addr) external checkPrivileges("") {
        if (addressLookup[msg.sender] != addressLookup[addr]) revert Unauthorized();
        _remove(addr);
    }

    function clusterAddresses(uint256 _clusterId) external view returns (address[] memory) {
        return _clusterAddresses[_clusterId].values();
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        if (addressLookup[addr] != 0) revert Registered();
        addressLookup[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
    }

    function _remove(address addr) internal {
        uint256 clusterId = addressLookup[addr];
        // If the cluster has valid names, prevent removing final address, regardless of what is supplied for addr
        if (_clusterNames[clusterId].length() > 0 && _clusterAddresses[clusterId].length() == 1) revert Invalid();
        delete addressLookup[addr];
        _clusterAddresses[clusterId].remove(addr);
        bytes32 walletName = reverseLookup[addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[addr];
        }
    }
}
