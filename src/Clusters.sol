// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Pricing} from "./Pricing.sol";

// Each cluster has an ID
// The ID is the unique identifier
// The ID points to a set of addresses
// Address can only be in one cluster at a time
// Can a cluster have multiple names? Can it not have a name?
// What should we call an address within a cluster?
// Do we constrain names to be 32 bytes? (32 chars)
// Where do we store expiries and how do we clear state?
// It's actually more complex, user money is stored in escrow and can be used to pay harberger tax on loan or get outbid
// And same for expiries, the bid is required to trigger. Need smooth mathematical functions here
// Can users set a canonical name for cluster?
// Should you be able to transfer name between clusters?
// How do we handle when an account gets hacked and kick everyone else out from valuable cluster?
// What do we do about everybody being in cluster 0? Treat it like a burn address of sorts.

contract Clusters {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    Pricing public pricing;

    uint256 public nextClusterId = 1;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) public addressLookup;

    /// @notice Which cluster a name belongs to
    mapping(string name => uint256 clusterId) public nameLookup;

    /// @notice Timestamp a name expires at
    mapping(string name => uint256 expiry) public nameExpiry;

    /// @notice Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set names) internal _clusterNames;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => string name) public canonicalClusterName;

    mapping(uint256 clusterId => mapping(address addr => bool invited)) public invited;

    constructor(address _pricing) {
        pricing = Pricing(_pricing);
    }

    /// ECONOMIC FUNCTIONS ///

    function buyName(string memory name, uint256 clusterId, uint256 numSeconds) external payable {
        // Check that name fits within bytes32
        require(bytes(name).length <= 32, "name too long");
        // Check that name is unused
        require(nameLookup[name] == 0, "name already bought");
        // TODO: issue refund
        require(msg.value >= pricing.getPrice(0.01 ether, numSeconds), "not enough eth");
        _assignName(name, clusterId, block.timestamp + numSeconds);
    }

    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(uint256 clusterId) external {}

    /// PUBLIC FUNCTIONS ///

    function create() external {
        _add(msg.sender, nextClusterId++);
    }

    function setCanonicalName(string memory name) external {
        uint256 currentCluster = addressLookup[msg.sender];
        require(nameLookup[name] == currentCluster, "don't own name");
        canonicalClusterName[currentCluster] = name;
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

    function kick(address addr) external {
        require(addressLookup[msg.sender] == addressLookup[addr], "not in same cluster");
        _remove(addr);
    }

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory) {
        return _clusterAddresses[clusterId].values();
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        invited[clusterId][addr] = false;
        addressLookup[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
    }

    function _remove(address addr) internal {
        uint256 currentCluster = addressLookup[addr];
        _clusterAddresses[currentCluster].remove(addr);
        invited[currentCluster][addr] = false;
    }

    function _assignName(string memory name, uint256 clusterId, uint256 expiry) internal {
        nameLookup[name] = clusterId;
        _clusterNames[clusterId].add(bytes32(bytes(name)));
        nameExpiry[name] = expiry;
    }

    /// STRING HELPERS ///

    /// @dev Returns a string from a small bytes32 string.
    function _fromSmallString(bytes32 smallString) internal pure returns (string memory result) {
        if (smallString == bytes32(0)) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, smallString)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, smallString)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }
}
