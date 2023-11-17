// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {NameManager} from "./NameManager.sol";

// Can a cluster have multiple names? (yes) Can it not have a name? (yes)
// Where do we store expiries (we dont, do we need to?) and how do we clear state? (pokeName() wipes state before transferring or expiring)
// It's actually more complex, user money is stored in escrow and can be used to pay harberger tax on loan or get outbid
// (name backing can only pay harberger tax, bids increase harberger tax, outbids refund previous bid)
// And same for expiries, the bid is required to trigger. Need smooth mathematical functions here (trigger /w pokeName() or bidName())
// Can users set a canonical name for cluster? Yes, they can own multiple names and they can also have zero names.
// Should you be able to transfer name between clusters? Yes, and how can they be traded? (transferName() updates relevant state)
// How do we handle when an account gets hacked and kick everyone else out from valuable cluster? Problem of success,
// can just ignore. Don't get phished, 2FA not worth it.
// What do we do about everybody being in cluster 0? Treat it like a burn address of sorts.
// (_clusterNames has names removed on expiry and 'checkPrivileges(name)' modifier prevents execution if addressLookup returns 0)
// What does the empty foobar/ resolver point to? CREATE2 Singlesig?

contract Clusters is NameManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal nextClusterId = 1;

    /// @notice Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    /// @notice Outstanding invitations to join a cluster
    mapping(uint256 clusterId => mapping(address addr => bool invited)) internal invited;

    error MulticallFailed();

    constructor(address _pricing) NameManager(_pricing) {}

    // TODO: Make this payable and pass along msg.value? As it stands insecure to make payable because of msg.value
    // reuse
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        bool success;
        unchecked {
            for (uint256 i = 0; i < data.length; ++i) {
                //slither-disable-next-line calls-loop,delegatecall-loop
                (success, results[i]) = address(this).delegatecall(data[i]);
                if (!success) revert MulticallFailed();
            }
        }
    }

    /// PUBLIC FUNCTIONS ///

    function create() external {
        _add(msg.sender, nextClusterId++);
    }

    function invite(address invitee) external {
        uint256 currentCluster = addressLookup[msg.sender];
        invited[currentCluster][invitee] = true;
    }

    function join(uint256 clusterId) external {
        require(invited[clusterId][msg.sender], "not invited");
        _add(msg.sender, clusterId);
    }

    function leave() external {
        _remove(msg.sender);
    }

    function remove(address addr) external {
        require(addressLookup[msg.sender] == addressLookup[addr], "not in same cluster");
        _remove(addr);
    }

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory) {
        return _clusterAddresses[clusterId].values();
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        require(addressLookup[addr] == 0, "already in cluster");
        invited[clusterId][addr] = false;
        addressLookup[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
    }

    function _remove(address addr) internal {
        uint256 currentCluster = addressLookup[addr];
        _clusterAddresses[currentCluster].remove(addr);
        invited[currentCluster][addr] = false;
    }
}
