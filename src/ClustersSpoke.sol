// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Follow https://docs.soliditylang.org/en/latest/style-guide.html for style

import {EnumerableSetLib} from "./EnumerableSetLib.sol";

import {NameManagerSpoke} from "./NameManagerSpoke.sol";

import {IClustersHub} from "./interfaces/IClustersHub.sol";

import {IEndpoint} from "./interfaces/IEndpoint.sol";

import {console2} from "forge-std/Test.sol";

contract ClustersSpoke is NameManagerSpoke {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    uint256 public nextClusterId = 1;

    /// @dev Enumerates all unverified addresses in a cluster
    mapping(uint256 clusterId => EnumerableSetLib.Bytes32Set addrs) internal _unverifiedAddresses;

    /// @dev Enumerates all verified addresses in a cluster
    mapping(uint256 clusterId => EnumerableSetLib.Bytes32Set addrs) internal _verifiedAddresses;

    constructor(address pricing_, address endpoint_, uint256 marketOpenTimestamp_)
        NameManagerSpoke(pricing_, endpoint_, marketOpenTimestamp_)
    {}

    /// USER-FACING FUNCTIONS ///

    // TODO: Determine if Endpoint will use this or remove it
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        if (msg.sender != endpoint) _inMulticall = true;
        results = new bytes[](data.length);
        bool success;

        // Iterate through each call
        for (uint256 i = 0; i < data.length; ++i) {
            //slither-disable-next-line calls-loop,delegatecall-loop
            (success, results[i]) = address(this).delegatecall(data[i]);
            if (!success) revert MulticallFailed();
        }

        if (_inMulticall) {
            bytes memory payload = abi.encodeWithSignature("multicall(bytes[])", results);
            IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
            _inMulticall = false;
        }
    }

    function getUnverifiedAddresses(uint256 clusterId) external view returns (bytes32[] memory) {
        return _unverifiedAddresses[clusterId].values();
    }

    function getVerifiedAddresses(uint256 clusterId) external view returns (bytes32[] memory) {
        return _verifiedAddresses[clusterId].values();
    }

    /// ENDPOINT FUNCTIONS ///

    function add(bytes32 msgSender, bytes32 addr) public payable onlyEndpoint returns (bytes memory) {
        _add(addr, addressToClusterId[msgSender]);
        return bytes("");
    }

    function verify(bytes32 msgSender, uint256 clusterId) public payable onlyEndpoint returns (bytes memory payload) {
        uint256 currentClusterId = addressToClusterId[msgSender];
        if (currentClusterId != 0) {
            // If msgSender is the last address in their cluster, take all of their names with them
            if (_verifiedAddresses[currentClusterId].length() == 1) {
                bytes32[] memory names = _clusterNames[currentClusterId].values();
                for (uint256 i; i < names.length; ++i) {
                    _transferName(names[i], currentClusterId, clusterId);
                }
            }
            _remove(msgSender, currentClusterId);
        }
        _verify(msgSender, clusterId);
        return bytes("");
    }

    function remove(bytes32 msgSender, bytes32 addr) public payable onlyEndpoint returns (bytes memory) {
        _remove(addr, addressToClusterId[msgSender]);
        return bytes("");
    }

    /// INTERNAL FUNCTIONS ///

    function _add(bytes32 addr, uint256 clusterId) internal {
        _unverifiedAddresses[clusterId].add(addr);
        emit Add(clusterId, addr);
    }

    function _verify(bytes32 addr, uint256 clusterId) internal {
        _unverifiedAddresses[clusterId].remove(addr);
        _verifiedAddresses[clusterId].add(addr);
        addressToClusterId[addr] = clusterId;
        emit Verify(clusterId, addr);
    }

    function _remove(bytes32 addr, uint256 clusterId) internal {
        _unverifiedAddresses[clusterId].remove(addr);
        if (addressToClusterId[addr] == clusterId) {
            delete addressToClusterId[addr];
            _verifiedAddresses[clusterId].remove(addr);
            bytes32 walletName = reverseLookup[addr];
            if (walletName != bytes32("")) {
                delete forwardLookup[clusterId][walletName];
                delete reverseLookup[addr];
            }
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
            _remove(addresses[i], clusterId);
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
