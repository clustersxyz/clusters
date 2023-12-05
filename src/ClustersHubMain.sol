// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Follow https://docs.soliditylang.org/en/latest/style-guide.html for style

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {NameManagerMain} from "./NameManagerMain.sol";

import {IClusters, IEndpoint} from "./IClusters.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/**
 * OPEN QUESTIONS/TODOS
 * Can you create a cluster without registering a name? No, there needs to be a bounty for adding others to your cluster
 * What does the empty foobar/ resolver point to?
 * If listings are offchain, then how can it hook into the onchain transfer function?
 * The first name added to a cluster should become the canonical name by default, every cluster should always have
 * canonical name
 */

contract ClustersHubMain is NameManagerMain {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    constructor(address pricing_, address endpoint_) NameManagerMain(pricing_, endpoint_) {}

    /// USER-FACING FUNCTIONS ///

    /// @dev For payable multicall to be secure, we cannot trust msg.value params in other external methods
    /// @dev Must instead do strict protocol invariant checking at the end of methods like Uniswap V2
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        bool success;

        // Iterate through each call
        for (uint256 i = 0; i < data.length; ++i) {
            //slither-disable-next-line calls-loop,delegatecall-loop
            (success, results[i]) = address(this).delegatecall(data[i]);
            if (!success) revert MulticallFailed();
        }

        _checkInvariant();
    }

    function create() public payable returns (bytes memory payload) {
        create(msg.sender);
        return bytes("");
    }

    function add(address addr) public payable returns (bytes memory payload) {
        add(msg.sender, addr);
        return bytes("");
    }

    function remove(address addr) public payable returns (bytes memory payload) {
        remove(msg.sender, addr);
        return bytes("");
    }

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory) {
        return _clusterAddresses[clusterId].values();
    }

    /// ENDPOINT FUNCTIONS ///

    function create(address msgSender) public payable onlyEndpoint(msgSender) {
        _add(msgSender, nextClusterId++);
    }

    function add(address msgSender, address addr) public payable onlyEndpoint(msgSender) {
        _checkZeroCluster(msgSender);
        if (addressToClusterId[addr] != 0) revert Registered();
        _add(addr, addressToClusterId[msgSender]);
    }

    function remove(address msgSender, address addr) public payable onlyEndpoint(msgSender) {
        _checkZeroCluster(msgSender);
        if (addressToClusterId[msgSender] != addressToClusterId[addr]) revert Unauthorized();
        _remove(addr);
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        if (addressToClusterId[addr] != 0) revert Registered();
        addressToClusterId[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
        emit Add(clusterId, addr);
    }

    function _remove(address addr) internal {
        uint256 clusterId = addressToClusterId[addr];
        // If the cluster has valid names, prevent removing final address, regardless of what is supplied for addr
        if (_clusterNames[clusterId].length() > 0 && _clusterAddresses[clusterId].length() == 1) revert Invalid();
        delete addressToClusterId[addr];
        _clusterAddresses[clusterId].remove(addr);
        bytes32 walletName = reverseLookup[addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[addr];
        }
        emit Remove(clusterId, addr);
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
