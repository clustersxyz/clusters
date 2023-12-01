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

    constructor(address _pricing) NameManager(_pricing) {}

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
        _add(msg.sender, nextClusterId++);
    }

    function add(address _addr) external checkPrivileges("") {
        if (addressLookup[_addr] != 0) revert Registered();
        _add(_addr, addressLookup[msg.sender]);
    }

    function remove(address _addr) external checkPrivileges("") {
        if (addressLookup[msg.sender] != addressLookup[_addr]) revert Unauthorized();
        _remove(_addr);
    }

    function clusterAddresses(uint256 _clusterId) external view returns (address[] memory) {
        return _clusterAddresses[_clusterId].values();
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address _addr, uint256 clusterId) internal {
        if (addressLookup[_addr] != 0) revert Registered();
        addressLookup[_addr] = clusterId;
        _clusterAddresses[clusterId].add(_addr);
    }

    function _remove(address _addr) internal {
        uint256 clusterId = addressLookup[_addr];
        // If the cluster has valid names, prevent removing final address, regardless of what is supplied for _addr
        if (_clusterNames[clusterId].length() > 0 && _clusterAddresses[clusterId].length() == 1) revert Invalid();
        delete addressLookup[_addr];
        _clusterAddresses[clusterId].remove(_addr);
        bytes32 walletName = reverseLookup[_addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[_addr];
        }
    }
}
