// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Follow https://docs.soliditylang.org/en/latest/style-guide.html for style

import {EnumerableSetLib} from "./EnumerableSetLib.sol";

import {NameManagerHub} from "./NameManagerHub.sol";

import {IClusters, IEndpoint} from "./IClusters.sol";

import {IEndpoint} from "./interfaces/IEndpoint.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/**
 * OPEN QUESTIONS/TODOS
 * Can you create a cluster without registering a name? No, there needs to be a bounty for adding others to your cluster
 * What does the empty foobar/ resolver point to?
 * If listings are offchain, then how can it hook into the onchain transfer function?
 * The first name added to a cluster should become the canonical name by default, every cluster should always have
 * canonical name
 */

contract ClustersHub is NameManagerHub {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    constructor(address pricing_, address endpoint_) NameManagerHub(pricing_, endpoint_) {}

    /// USER-FACING FUNCTIONS ///

    /// @dev For payable multicall to be secure, we cannot trust msg.value params in other external methods
    /// @dev Must instead do strict protocol invariant checking at the end of methods like Uniswap V2
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        _inMulticall = true;
        results = new bytes[](data.length);
        bool success;
        bytes4 multicallSig = bytes4(keccak256(bytes("multicall(bytes[])")));

        // Iterate through each call
        for (uint256 i; i < data.length; ++i) {
            bytes memory currentCall = data[i];
            // Check selector to block nested multicalls
            bytes4 signature;
            assembly {
                signature := mload(add(currentCall, 32))
            }
            if (signature == multicallSig) {
                revert MulticallFailed();
            }
            //slither-disable-next-line calls-loop,delegatecall-loop
            (success, results[i]) = address(this).delegatecall(data[i]);
            if (!success) revert MulticallFailed();
        }

        _checkInvariant();

        bytes memory payload = abi.encodeWithSignature("multicall(bytes[])", results);
        IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
        _inMulticall = false;
    }

    function add(bytes32 addr) external payable returns (bytes memory payload) {
        return add(_addressToBytes32(msg.sender), addr);
    }

    function verify(uint256 clusterId) external payable returns (bytes memory payload) {
        return verify(_addressToBytes32(msg.sender), clusterId);
    }

    function remove(bytes32 addr) external payable returns (bytes memory payload) {
        return remove(_addressToBytes32(msg.sender), addr);
    }

    function getUnverifiedAddresses(uint256 clusterId) external view returns (bytes32[] memory) {
        return _unverifiedAddresses[clusterId].values();
    }

    /// ENDPOINT FUNCTIONS ///

    function add(bytes32 msgSender, bytes32 addr)
        public
        payable
        onlyEndpoint(msgSender)
        returns (bytes memory payload)
    {
        uint256 clusterId = addressToClusterId[msgSender];
        if (clusterId == 0) revert NoCluster();
        if (_verifiedAddresses[clusterId].contains(addr)) revert Registered();
        _add(addr, clusterId);

        payload = abi.encodeWithSignature("add(bytes32,bytes32)", msgSender, addr);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    function verify(bytes32 msgSender, uint256 clusterId)
        public
        payable
        onlyEndpoint(msgSender)
        returns (bytes memory payload)
    {
        if (!_unverifiedAddresses[clusterId].contains(msgSender)) revert Unauthorized();
        uint256 currentClusterId = addressToClusterId[msgSender];
        if (currentClusterId != 0) {
            // If msgSender is the last address in their cluster, take all of their names with them
            if (_verifiedAddresses[currentClusterId].length() == 1) {
                bytes32[] memory names = _clusterNames[currentClusterId].values();
                for (uint256 i; i < names.length; ++i) {
                    _transferName(names[i], currentClusterId, clusterId);
                }
            }
            _remove(msgSender);
        }
        _verify(msgSender, clusterId);

        payload = abi.encodeWithSignature("verify(bytes32,uint256)", msgSender, clusterId);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    function remove(bytes32 msgSender, bytes32 addr)
        public
        payable
        onlyEndpoint(msgSender)
        returns (bytes memory payload)
    {
        uint256 clusterId = addressToClusterId[msgSender];
        if (clusterId == 0) revert NoCluster();
        if (clusterId != addressToClusterId[addr]) revert Unauthorized();
        // If the cluster has valid names, prevent removing final address, regardless of what is supplied for addr
        if (_clusterNames[clusterId].length() > 0 && _verifiedAddresses[clusterId].length() == 1) revert Invalid();
        _remove(addr);

        payload = abi.encodeWithSignature("remove(bytes32,bytes32)", msgSender, addr);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        addressToClusterId[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
        emit Add(clusterId, addr);
    }

    function _verify(bytes32 addr, uint256 clusterId) internal {
        _unverifiedAddresses[clusterId].remove(addr);
        _verifiedAddresses[clusterId].add(addr);
        addressToClusterId[addr] = clusterId;
        emit Verify(clusterId, addr);
    }

    function _remove(bytes32 addr) internal {
        uint256 clusterId = addressToClusterId[addr];
        delete addressToClusterId[addr];
        _verifiedAddresses[clusterId].remove(addr);
        bytes32 walletName = reverseLookup[addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[addr];
        }
        emit Remove(clusterId, addr);
    }

    function _hookCreate(bytes32 addr) internal override {
        uint256 clusterId = nextClusterId++;
        _verifiedAddresses[clusterId].add(addr);
        addressToClusterId[addr] = clusterId;
    }

    function _hookDelete(uint256 clusterId) internal override {
        bytes32[] memory addresses = _verifiedAddresses[clusterId].values();
        for (uint256 i; i < addresses.length; ++i) {
            _remove(addresses[i]);
        }
        emit Delete(clusterId);
    }

    function _hookCheck(uint256 clusterId) internal view override {
        if (clusterId == 0) return;
        if (_verifiedAddresses[clusterId].length() == 0) revert Invalid();
    }

    function _hookCheck(uint256 clusterId, bytes32 addr) internal view override {
        if (!_unverifiedAddresses[clusterId].contains(addr) && clusterId != addressToClusterId[addr]) {
            revert Unauthorized();
        }
    }
}
