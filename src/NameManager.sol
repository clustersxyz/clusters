// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Pricing} from "./Pricing.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
contract NameManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    error NoBid();
    error Invalid();
    error NoCluster();
    error TransferFailed();

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
        // TODO: Evaluate if updatedTimestamp is necessary
        address bidder;
    }

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(uint256 bidId => Bid) internal bids;

    /// @notice Counter for next bidId, always +1 over most recent bid
    uint256 internal nextBidId = 1;

    /// @notice Set of bids per name allows for bid enumeration
    mapping(bytes32 name => EnumerableSet.UintSet bidIds) internal bidsForName;

    /// @notice Since each address can only bid on a name once, this helps for bid lookup
    mapping(bytes32 name => mapping(address bidder => uint256 bidId)) internal bidLookup;

    /// @notice Internal accounting for all bid ETH held in contract
    uint256 internal bidPool;

    /// @notice Restrict certain functions to those who have created a cluster for their address
    modifier hasCluster() {
        // Revert if msg.sender doesn't have a cluster
        if (addressLookup[msg.sender] == 0) revert NoCluster();
        _;
    }

    constructor(address _pricing) {
        pricing = Pricing(_pricing);
    }

    /// ECONOMIC FUNCTIONS ///

    function buyName(string memory _name, uint256 clusterId) external payable hasCluster {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
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
        if (name == bytes32("")) revert Invalid();
        uint256 currentCluster = addressLookup[msg.sender];
        require(_clusterNames[currentCluster].contains(name), "not name owner");
        _transferName(name, currentCluster, toClusterId);
    }

    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and transfer names upon expiry to highest
    ///         sufficient bidder. If no bids above yearly minimum, delete name registration.
    function pokeName(string memory _name) public {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        PriceIntegral memory integral = priceIntegral[name];
        (uint256 spent, uint256 newPrice) = pricing.getIntegratedPrice(
            integral.lastUpdatedPrice,
            block.timestamp - integral.lastUpdatedTimestamp,
            block.timestamp - integral.lastUpdatedTimestamp
        );
        // Name expires only once out of eth
        uint256 backing = ethBacking[name];
        // If out of backing (expired), transfer to highest sufficient bidder or delete registration
        if (spent >= backing) {
            // Transfer backing to protocol and clear accounting
            unchecked {
                protocolRevenue += backing;
                ethBackingTotal -= backing;
            }
            delete ethBacking[name];
            // Check for and transfer to highest sufficient bidder, if no bids it will be address(0) which is cluster 0
            address highestBidder = _processBids(name);
            _transferName(name, nameLookup[name], addressLookup[highestBidder]);
        } else {
            // Process price data update
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

    /// @notice Checks for highest sufficient (yearly minimum required) bid and returns the bidder, if any
    /// @dev Returns address(0) if no bids are sufficient
    /// @return highestBidder Highest sufficient bidder
    function _processBids(bytes32 name) internal returns (address highestBidder) {
        // Cache all current bidIds
        uint256[] memory bidIds = bidsForName[name].values();
        // Iterate through all bids looking for the highest one
        uint256 highestBidIndex;
        uint256 highestBid;
        for (uint256 i; i < bidIds.length;) {
            uint256 bid = bids[bidIds[i]].ethAmount;
            if (bid > highestBid) {
                highestBidIndex = i;
                highestBid = bid;
            }
            unchecked { ++i; }
        }
        // Ensure highest bid is at least above minimum annual price before transferring name, address is 0x0 otherwise
        if (highestBid >= pricing.minAnnualPrice()) {
            // Retrieve highest bid info
            uint256 bidId = bidIds[highestBidIndex];
            highestBidder = bids[bidId].bidder;
            // Process internal accounting changes
            unchecked {
                ethBacking[name] += highestBid;
                ethBackingTotal += highestBid;
                bidPool -= highestBid;
            }
            // Purge highest bidder's bid
            _deleteBid(bidId);
            // Process name registration and transfer
            priceIntegral[name] = PriceIntegral({
                name: name,
                lastUpdatedTimestamp: block.timestamp,
                lastUpdatedPrice: pricing.minAnnualPrice(),
                maxExpiry: block.timestamp + uint256(pricing.getMaxDuration(pricing.minAnnualPrice(), highestBid))
            });
        }
    }

    /// @dev Transfer cluster name or delete cluster name without checking auth
    /// @dev Delete by transferring to cluster id 0
    function _transferName(bytes32 name, uint256 fromClusterId, uint256 toClusterId) internal {
        // If name is canonical cluster name for sending cluster, remove that assignment
        if (canonicalClusterName[fromClusterId] == name) {
            delete canonicalClusterName[fromClusterId];
        }
        // Assign name to new cluster, otherwise unassign
        if (toClusterId != 0) {
            // Assign name to new cluster
            _assignName(name, toClusterId);
            // Remove from old cluster
            _clusterNames[fromClusterId].remove(name);
        } else {
            // Purge name assignment and remove from cluster
            _unassignName(name, fromClusterId);
        }
    }

    /// @notice Place bids on valid names. Subsequent calls increases existing bid. If name is expired, transfer to
    ///         highest sufficient bidder or delete if none exist.
    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(string memory _name) external payable hasCluster {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        // If name exists, process bid
        if (nameLookup[name] != 0) {
            // Retrieve existing bid, if any
            uint256 bidId = bidLookup[name][msg.sender];
            // If msg.sender hasn't placed a bid, process new bid
            if (bidId == 0) {
                // Retrieve bidId, increment bidId pointer, and increment total bid accounting
                unchecked {
                    bidId = nextBidId++;
                    bidPool += msg.value;
                }
                // Store bid information
                bids[bidId] = Bid({
                    name: name,
                    ethAmount: msg.value,
                    createdTimestamp: block.timestamp,
                    bidder: msg.sender
                });
                // Log bidId under name
                bidsForName[name].add(bidId);
                // Log bidId under msg.sender
                bidLookup[name][msg.sender] = bidId;
            }
            // If bid does exist, increment existing bid by msg.value
            else {
                unchecked {
                    bids[bidId].ethAmount += msg.value;
                    bidPool += msg.value;
                }
            }

            // Update name status and transfer to highest sufficient bidder if expired
            pokeName(_name);
        }
    }

    /// @notice Reduce bid and refund difference
    function reduceBid(string memory _name, uint256 amount) external {
        // Retrieve existing bid
        bytes32 name = _toBytes32(_name);
        uint256 bidId = bidLookup[name][msg.sender];
        // Revert if no bid exists
        if (bidId == 0) revert NoBid();
        // Retrieve bid value and confirm amount isn't larger than it
        uint256 bid = bids[bidId].ethAmount;
        if (amount > bid) revert Invalid();
        // If reducing bid to 0, revoke altogether
        if (bid - amount == 0) {
            _deleteBid(bidId);
        }
        // Otherwise, decrease bid
        else {
            unchecked { bids[bidId].ethAmount -= amount; }
        }
        // Reduce bidPool accordingly
        unchecked { bidPool -= amount; }
        // Transfer bid reduction after all state is purged to prevent reentrancy
        (bool success, ) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert TransferFailed();
    }

    /// @notice Allow valid bidder to revoke bid and get refunded
    function revokeBid(string memory _name) external {
        // Retrieve existing bid
        bytes32 name = _toBytes32(_name);
        uint256 bidId = bidLookup[name][msg.sender];
        // Revert if no bid exists
        if (bidId == 0) revert NoBid();
        // Retrieve bid value and purge all bid state
        uint256 bid = bids[bidId].ethAmount;
        unchecked { bidPool -= bid; }
        _deleteBid(bidId);
        // Transfer revoked bid after all state is purged to prevent reentrancy
        (bool success, ) = payable(msg.sender).call{ value: bid }("");
        if (!success) revert TransferFailed();
    }

    /// @notice Internal function to delete bid storage
    /// @dev Does not decrement bidPool!
    function _deleteBid(uint256 bidId) internal {
        Bid memory bid = bids[bidId];
        bytes32 name = bid.name;
        address bidder = bid.bidder;
        delete bidLookup[name][bidder];
        bidsForName[name].remove(bidId);
        delete bids[bidId];
    }

    /// LOCAL NAME MANAGEMENT ///

    function setCanonicalName(string memory _name) external hasCluster {
        bytes32 name = _toBytes32(_name);
        uint256 currentCluster = addressLookup[msg.sender];
        require(nameLookup[name] == currentCluster, "don't own name");
        canonicalClusterName[currentCluster] = name;
    }

    function removeCanonicalName() external hasCluster {
        uint256 currentCluster = addressLookup[msg.sender];
        delete canonicalClusterName[currentCluster];
    }

    function setWalletName(string memory _walletName) external hasCluster {
        bytes32 walletName = _toBytes32(_walletName);
        uint256 currentCluster = addressLookup[msg.sender];
        require(forwardLookup[currentCluster][walletName] == address(0), "name already in use for cluster");
        reverseLookup[msg.sender] = walletName;
        forwardLookup[currentCluster][walletName] = msg.sender;
    }

    function removeWalletName() external hasCluster {
        uint256 currentCluster = addressLookup[msg.sender];
        bytes32 walletName = reverseLookup[msg.sender];
        delete reverseLookup[msg.sender];
        delete forwardLookup[currentCluster][walletName];
    }

    function _assignName(bytes32 name, uint256 clusterId) internal {
        nameLookup[name] = clusterId;
        _clusterNames[clusterId].add(name);
    }

    function _unassignName(bytes32 name, uint256 clusterId) internal {
        nameLookup[name] = 0;
        _clusterNames[clusterId].remove(name);
    }

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