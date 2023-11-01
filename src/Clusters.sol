// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Pricing} from "./Pricing.sol";

// Can a cluster have multiple names? Can it not have a name?
// Where do we store expiries and how do we clear state?
// It's actually more complex, user money is stored in escrow and can be used to pay harberger tax on loan or get outbid
// And same for expiries, the bid is required to trigger. Need smooth mathematical functions here
// Can users set a canonical name for cluster? Yes, they can own multiple names and they can also have zero names.
// Should you be able to transfer name between clusters? Yes, and how can they be traded?
// How do we handle when an account gets hacked and kick everyone else out from valuable cluster? Problem of success,
// can just ignore. Don't get phished, 2FA not worth it.
// What do we do about everybody being in cluster 0? Treat it like a burn address of sorts.
// What does the empty foobar/ resolver point to? CREATE2 Singlesig?

contract Clusters {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    Pricing public pricing;

    uint256 public nextClusterId = 1;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) public addressLookup;

    /// @notice Which cluster a name belongs to
    mapping(bytes32 name => uint256 clusterId) public nameLookup;

    /// @notice Timestamp a name expires at
    mapping(bytes32 name => uint256 expiry) public nameExpiry;

    /// @notice Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set names) internal _clusterNames;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => bytes32 name) public canonicalClusterName;

    /// @notice Outstanding invitations to join a cluster
    mapping(uint256 clusterId => mapping(address addr => bool invited)) public invited;

    /// @notice For example lookup[17]["hot"] -> 0x123...
    mapping(uint256 clusterId => mapping(bytes32 walletName => address wallet)) internal forwardLookup;

    /// @notice For example lookup[0x123...] -> "hot", then combine with cluster name in a diff method
    mapping(address wallet => bytes32 walletName) internal reverseLookup;

    error MulticallFailed();

    constructor(address _pricing) {
        pricing = Pricing(_pricing);
    }

    // TODO: Make this payable and pass along msg.value?
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

    /// ECONOMIC FUNCTIONS ///

    function buyName(string memory name, uint256 clusterId, uint256 numSeconds) external payable {
        bytes32 name = _toBytes32(name);
        // Check that name is unused
        require(nameLookup[name] == 0, "name already bought");
        // TODO: issue refund
        require(msg.value >= pricing.getPrice(0.01 ether, numSeconds), "not enough eth");
        _assignName(name, clusterId, block.timestamp + numSeconds);
    }

    /// @notice Move name from one cluster to another without payment
    function transferName(string memory name, uint256 toClusterId) external {
        uint256 currentCluster = addressLookup[msg.sender];
        require(_clusterNames[currentCluster].contains(_toBytes32(name)), "not name owner");
        if (canonicalClusterName[currentCluster] == _toBytes32(name)) {
            delete canonicalClusterName[currentCluster];
        }
        _clusterNames[currentCluster].remove(_toBytes32(name));
        _clusterNames[toClusterId].add(_toBytes32(name));
    }

    function bidName(string memory name, uint256 clusterId) external payable {
        // Deposit eth into escrow
        uint256 bidAmount = msg.value;
        // Should people have to precommit to time spent in escrow? No we want continuous
    }

    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(uint256 clusterId) external {}

    /// PUBLIC FUNCTIONS ///

    function create() external {
        _add(msg.sender, nextClusterId++);
    }

    function setCanonicalName(string memory name) external {
        bytes32 name = _toBytes32(name);
        uint256 currentCluster = addressLookup[msg.sender];
        require(nameLookup[name] == currentCluster, "don't own name");
        canonicalClusterName[currentCluster] = name;
    }

    function setWalletName(string memory walletName) external {
        bytes32 walletName = _toBytes32(walletName);
        uint256 currentCluster = addressLookup[msg.sender];
        require(forwardLookup[currentCluster][walletName] == address(0), "name already in use for cluster");
        reverseLookup[msg.sender] = walletName;
        forwardLookup[currentCluster][walletName] = msg.sender;
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

    function _assignName(bytes32 name, uint256 clusterId, uint256 expiry) internal {
        nameLookup[name] = clusterId;
        _clusterNames[clusterId].add(name);
        nameExpiry[name] = expiry;
    }

    /// STRING HELPERS ///

    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        require(smallBytes.length <= 32, "name too long");
        return bytes32(smallBytes);
    }

    /// @dev Returns a string from a small bytes32 string.
    function _toSmallString(bytes32 smallBytes) internal pure returns (string memory result) {
        if (smallBytes == bytes32(0)) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, smallBytes)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, smallBytes)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }
}
