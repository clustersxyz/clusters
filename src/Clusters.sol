// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {NameManager} from "./NameManager.sol";

import {IClusters} from "./IClusters.sol";

// Can a cluster have multiple names? (yes) Can it not have a name? (yes)
// Where do we store expiries (we dont, do we need to?) and how do we clear state? (pokeName() wipes state before
// transferring or expiring)
// It's actually more complex, user money is stored in escrow and can be used to pay harberger tax on loan or get outbid
// (name backing can only pay harberger tax, bids increase harberger tax, outbids refund previous bid)
// And same for expiries, the bid is required to trigger. Need smooth mathematical functions here (trigger /w pokeName()
// or bidName())
// Can users set a canonical name for cluster? Yes, they can own multiple names and they can also have zero names.
// Should you be able to transfer name between clusters? Yes, and how can they be traded? (transferName() updates
// relevant state)
// How do we handle when an account gets hacked and kick everyone else out from valuable cluster? Problem of success,
// can just ignore. Don't get phished, 2FA not worth it.
// What do we do about everybody being in cluster 0? Treat it like a burn address of sorts.
// (_clusterNames has names removed on expiry and 'checkPrivileges(name)' modifier prevents execution if addressLookup
// returns 0)
// What does the empty foobar/ resolver point to? CREATE2 Singlesig?

contract Clusters is NameManager {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes4 internal constant BUY_NAME_SIG = bytes4(keccak256("buyName(string,uint256)"));
    bytes4 internal constant FUND_NAME_SIG = bytes4(keccak256("fundName(string,uint256)"));
    bytes4 internal constant BID_NAME_SIG = bytes4(keccak256("bidName(string,uint256)"));

    /// @dev Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    constructor(address _pricing) NameManager(_pricing) {}

    function _determineCallValue(bytes memory _data) internal pure returns (uint256) {
        // Extract the function signature
        bytes4 sig;
        assembly {
            sig := mload(add(_data, 32))
        }

        // Match the function signature
        if (sig == BUY_NAME_SIG || sig == FUND_NAME_SIG || sig == BID_NAME_SIG) {
            // Read the memory offset (location) of the string
            uint256 stringOffset;
            assembly {
                stringOffset := mload(add(_data, 36)) // 4 bytes sig + 32 bytes for offset
            }
            // Read the length of the string stored in the 32 bytes after the offset
            uint256 stringLength;
            assembly {
                stringLength := mload(add(_data, add(36, stringOffset))) // 4 bytes sig + 32 bytes offset
            }
            // Calculate the position of the _value parameter (32 bytes after the offset, immediately after length)
            uint256 valueOffset = stringOffset + stringLength + 32;
            // Extract the _value parameter
            uint256 _value;
            assembly {
                _value := mload(add(_data, add(32, valueOffset))) // Corrected for 32 byte word size
            }
            return _value;
        }
        // Handle unmatched function signatures
        return 0;
    }

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

    function leave() external checkPrivileges("") {
        _remove(msg.sender);
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

    function _addressToBytes32(address _addr) internal pure returns (bytes32 addr) {
        return bytes32(uint256(uint160(_addr)));
    }
}
