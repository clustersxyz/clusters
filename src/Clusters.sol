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

    uint256 public nextClusterId = 1;

    /// @notice Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    /// @notice Outstanding invitations to join a cluster
    mapping(uint256 clusterId => mapping(address addr => bool invited)) public invited;

    error MulticallFailed();

    constructor(address _pricing) NameManager(_pricing) {}

    // TODO: Make this payable and pass along msg.value? As it stands insecure to make payable because of msg.value
    // reuse (I don't think this is a good idea because all payable NameManager functions would need a value param, or
    // we would have to externalize NameManager so TXs to it can be individually payable)
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
        if(!invited[clusterId][msg.sender]) revert Unauthorized();
        _add(msg.sender, clusterId);
    }

    // NOTE: What do we do about preventing someone from removing all of their addresses from a cluster? We will need
    // to enumerate cluster addresses if we are to know if addr is the last assigned to the cluster.

    function remove(address addr) external {
        if(addressLookup[msg.sender] != addressLookup[addr]) revert Unauthorized();
        _remove(addr);
    }

    function leave() external {
        _remove(msg.sender);
    }

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory) {
        return _clusterAddresses[clusterId].values();
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address _addr, uint256 clusterId) internal {
        if(addressLookup[_addr] != 0) revert Registered();
        delete invited[clusterId][_addr];
        addressLookup[_addr] = clusterId;
        _clusterAddresses[clusterId].add(_addr);
    }

    function _remove(address _addr) internal {
        uint256 clusterId = addressLookup[_addr];
        delete invited[clusterId][_addr];
        delete addressLookup[_addr];
        _clusterAddresses[clusterId].remove(_addr);
        bytes32 walletName = reverseLookup[_addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[_addr];
        }
    }
}
