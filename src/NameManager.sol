// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Pricing} from "./Pricing.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
contract NameManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    Pricing internal pricing;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) internal addressLookup;

    /// @notice Which cluster a name belongs to
    mapping(bytes32 name => uint256 clusterId) internal nameLookup;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => bytes32 name) internal canonicalClusterName;

    /// @notice For example lookup[17]["hot"] -> 0x123...
    mapping(uint256 clusterId => mapping(bytes32 walletName => address wallet)) internal forwardLookup;

    /// @notice For example lookup[0x123...] -> "hot", then combine with cluster name in a diff method
    mapping(address wallet => bytes32 walletName) internal reverseLookup;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set names) internal _clusterNames;

    /// @notice The amount of money backing each name registration
    mapping(bytes32 name => uint256 amount) internal ethBacking;

    /// @notice Total amount of ETH backing name registrations
    uint256 internal ethBackingTotal;

    /// @notice Amount of eth that's transferred from ethBacking to the protocol
    uint256 internal protocolRevenue;

    struct PriceIntegral {
        bytes32 name;
        uint256 lastUpdatedTimestamp;
        uint256 lastUpdatedPrice;
        uint256 maxExpiry;
    }

    mapping(bytes32 name => PriceIntegral integral) internal priceIntegral;

    /// @notice All relevant information for an individual bid
    struct Bid {
        bytes32 name;
        uint256 ethAmount;
        uint256 createdTimestamp;
        address bidder;
    }

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(uint256 bidId => Bid) internal bids;

    /// @notice Counter for next bidId, always +1 over most recent bid
    uint256 internal nextBidId = 1;

    mapping(bytes32 name => EnumerableSet.UintSet bidIds) internal bidsForName;

    mapping(bytes32 name => mapping(address bidder => uint256 bidId)) internal bidLookup;

    uint256 internal bidPool;

    constructor(address _pricing) {
        pricing = Pricing(_pricing);
    }

    /// ECONOMIC FUNCTIONS ///

    function buyName(string memory _name, uint256 clusterId) external payable {
        bytes32 name = _toBytes32(_name);
        // Check that name is unused
        require(nameLookup[name] == 0, "name already bought");
        unchecked {
            ethBacking[name] += msg.value;
            ethBackingTotal += msg.value;
        }
        priceIntegral[name] = PriceIntegral({
            name: name,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice(),
            maxExpiry: block.timestamp + uint256(pricing.getMaxDuration(pricing.minAnnualPrice(), msg.value))
        });
        _assignName(name, clusterId);
    }

    /// @notice Move name from one cluster to another without payment
    function transferName(string memory _name, uint256 toClusterId) external {
        bytes32 name = _toBytes32(_name);
        uint256 currentCluster = addressLookup[msg.sender];
        require(_clusterNames[currentCluster].contains(name), "not name owner");
        _transferName(name, currentCluster, toClusterId);
    }

    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and delete expired names
    function pokeName(string memory _name) public {
        bytes32 name = _toBytes32(_name);
        PriceIntegral memory integral = priceIntegral[name];
        (uint256 spent, uint256 newPrice) = pricing.getIntegratedPrice(
            integral.lastUpdatedPrice,
            block.timestamp - integral.lastUpdatedTimestamp,
            block.timestamp - integral.lastUpdatedTimestamp
        );
        // Name expires only once out of eth
        uint256 backing = ethBacking[name];
        if (spent >= backing) {
            unchecked {
                protocolRevenue += backing;
                ethBackingTotal -= backing;
            }
            ethBacking[name] = 0;
            _transferName(name, nameLookup[name], 0);
        } else {
            unchecked {
                protocolRevenue += spent;
                ethBacking[name] -= spent;
                ethBackingTotal -= backing;
            }
            priceIntegral[name] = PriceIntegral({
                name: name,
                lastUpdatedTimestamp: block.timestamp,
                lastUpdatedPrice: newPrice,
                maxExpiry: 0
            });
        }
    }

    /// @dev Transfer cluster name or delete cluster name without checking auth
    /// @dev Delete by transferring to cluster id 0
    function _transferName(bytes32 name, uint256 fromClusterId, uint256 toClusterId) internal {
        if (canonicalClusterName[fromClusterId] == name) {
            delete canonicalClusterName[fromClusterId];
        }
        _clusterNames[fromClusterId].remove(name);
        if (toClusterId != 0) {
            _clusterNames[toClusterId].add(name);
        }
    }

    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(string memory _name) external payable {
        bytes32 name = _toBytes32(_name);
        // Update name status prior to bid processing so expired names can be handled during bid processing
        pokeName(_name);
        // Retrieve existing bid, if any
        uint256 bidId = bidLookup[name][msg.sender];
        // If msg.sender hasn't placed a bid, process new bid
        if (bidId == 0) {
            unchecked {
                // Retrieve bidId and increment pointer
                bidId = nextBidId++;
                // Increment total bid accounting
                bidPool += msg.value;
            }
            bids[bidId] = Bid({
                name: name,
                ethAmount: msg.value,
                createdTimestamp: block.timestamp,
                bidder: msg.sender
            });
            // Log bidId for name
            bidsForName[name].add(bidId);
            // Log bidId for msg.sender
            bidLookup[name][msg.sender] = bidId;
        }
        // If bid does exist, increment existing bid by msg.value
        else {
            unchecked {
                // Increment existing bid
                bids[bidId].ethAmount += msg.value;
                // Increment total bid accounting
                bidPool += msg.value;
            }
        }
    }

    /// LOCAL NAME MANAGEMENT ///

    function setCanonicalName(string memory _name) external {
        bytes32 name = _toBytes32(_name);
        uint256 currentCluster = addressLookup[msg.sender];
        require(nameLookup[name] == currentCluster, "don't own name");
        canonicalClusterName[currentCluster] = name;
    }

    function setWalletName(string memory _walletName) external {
        bytes32 walletName = _toBytes32(_walletName);
        uint256 currentCluster = addressLookup[msg.sender];
        require(forwardLookup[currentCluster][walletName] == address(0), "name already in use for cluster");
        reverseLookup[msg.sender] = walletName;
        forwardLookup[currentCluster][walletName] = msg.sender;
    }

    function _assignName(bytes32 name, uint256 clusterId) internal {
        nameLookup[name] = clusterId;
        _clusterNames[clusterId].add(name);
    }

    function _unassignName(bytes32 name, uint256 clusterId) internal {}

    /// STRING HELPERS ///

    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        require(smallBytes.length <= 32, "name too long");
        return bytes32(smallBytes);
    }

    /// @dev Returns a string from a small bytes32 string.
    function _toString(bytes32 smallBytes) internal pure returns (string memory result) {
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
