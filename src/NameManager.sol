// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {Pricing} from "./Pricing.sol";

import {IClusters} from "./IClusters.sol";

import {console2} from "forge-std/Test.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
abstract contract NameManager is IClusters {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 internal constant BID_TIMELOCK = 30 days;

    Pricing internal pricing;

    uint256 public nextClusterId = 1;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) public addressLookup;

    /// @notice Which cluster a name belongs to
    mapping(bytes32 name => uint256 clusterId) public nameLookup;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => bytes32 name) public canonicalClusterName;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set names) internal _clusterNames;

    /// @notice For example lookup[17]["hot"] -> 0x123...
    mapping(uint256 clusterId => mapping(bytes32 walletName => address wallet)) public forwardLookup;

    /// @notice For example lookup[0x123...] -> "hot", then combine with cluster name in a diff method
    mapping(address wallet => bytes32 walletName) public reverseLookup;

    /// @notice Data required for proper harberger tax calculation when pokeName() is called
    mapping(bytes32 name => IClusters.PriceIntegral integral) public priceIntegral;

    /// @notice Amount of eth that's transferred from ethBacking to the protocol
    uint256 public protocolRevenue;

    /// @notice The amount of money backing each name registration
    mapping(bytes32 name => uint256 amount) public ethBacking;

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(bytes32 name => IClusters.Bid bidData) public bids;

    /// @notice Failed bid refunds are pooled so we don't have to revert when the highest bid is outbid
    mapping(address bidder => uint256 refund) public bidRefunds;

    /// @notice Ensure msg.sender has a cluster or owns a name
    modifier checkPrivileges(string memory _name) {
        // Revert if msg.sender has no cluster in all cases
        if (addressLookup[msg.sender] == 0) revert NoCluster();
        // If empty _name parameter, only check cluster ownership
        if (bytes(_name).length == 0) {
            _;
        } else {
            // Otherwise make sure name belongs to msg.sender's clusterId
            console2.log(addressLookup[msg.sender], nameLookup[_toBytes32(_name)]);
            if (addressLookup[msg.sender] != nameLookup[_toBytes32(_name)]) revert Unauthorized();
            _;
        }
    }

    constructor(address _pricing) {
        pricing = Pricing(_pricing);
    }

    /// VIEW FUNCTIONS ///

    /// @notice Get all names owned by a cluster
    /// @return names Array of names in bytes32 format
    function getClusterNames(uint256 clusterId) external view returns (bytes32[] memory names) {
        return _clusterNames[clusterId].values();
    }

    /// @notice Get Bid struct from storage
    /// @return bid Bid struct
    function getBid(bytes32 name) external view returns (IClusters.Bid memory bid) {
        return bids[name];
    }

    /// ECONOMIC FUNCTIONS ///

    /// @notice Buy unregistered name. Must pay at least minimum yearly payment.
    function buyName(string memory _name) external payable checkPrivileges("") {
        bytes32 name = _toBytes32(_name);
        uint256 clusterId = addressLookup[msg.sender];
        console2.log(_name, clusterId);
        if (name == bytes32("")) revert Invalid();
        // Check that name is unused and sufficient payment is made
        if (nameLookup[name] != 0) revert Registered();
        if (msg.value < pricing.minAnnualPrice()) revert Insufficient();
        // Process price accounting updates
        unchecked {
            ethBacking[name] += msg.value;
        }
        priceIntegral[name] = IClusters.PriceIntegral({
            name: name,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice(),
            maxExpiry: block.timestamp + uint256(pricing.getMaxDuration(pricing.minAnnualPrice(), msg.value))
        });
        _assignName(name, clusterId);
        emit BuyName(_name, clusterId);
    }

    /// @notice Buy unregistered name. Must pay at least minimum yearly payment.
    function buyName(string memory _name, uint256 clusterId) public payable checkPrivileges("") {
        bytes32 name = _toBytes32(_name);
        uint256 clusterId = nameLookup[name];
        if (name == bytes32("")) revert Invalid();
        // Check that name is unused and sufficient payment is made
        if (nameLookup[name] != 0) revert Registered();
        if (msg.value < pricing.minAnnualPrice()) revert Insufficient();
        // Process price accounting updates
        unchecked {
            ethBacking[name] += msg.value;
        }
        priceIntegral[name] = IClusters.PriceIntegral({
            name: name,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice(),
            maxExpiry: block.timestamp + uint256(pricing.getMaxDuration(pricing.minAnnualPrice(), msg.value))
        });
        _assignName(name, clusterId);
        emit BuyName(_name, clusterId);
    }

    /// @notice Fund an existing and specific name, callable by anyone
    function fundName(string memory _name) external payable {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        if (nameLookup[name] == 0) revert Unregistered();
        unchecked {
            ethBacking[name] += msg.value;
        }
        emit FundName(_name, msg.sender, msg.value);
    }

    /// @notice Move name from one cluster to another without payment
    function transferName(string memory _name, uint256 toClusterId) external checkPrivileges(_name) {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        if (toClusterId >= nextClusterId) revert Unregistered();
        uint256 currentCluster = addressLookup[msg.sender];
        _transferName(name, currentCluster, toClusterId);
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
            // Assign name to new cluster, _unassignName() isn't used because it resets nameLookup
            _assignName(name, toClusterId);
            _clusterNames[fromClusterId].remove(name);
            // Purge canonical name if necessary
            if (canonicalClusterName[fromClusterId] == name) delete canonicalClusterName[fromClusterId];
        } else {
            // Purge name assignment and remove from cluster
            _unassignName(name, fromClusterId);
        }
        emit TransferName(name, fromClusterId, toClusterId);
    }

    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and transfer names upon expiry to highest
    ///         sufficient bidder. If no bids above yearly minimum, delete name registration.
    function pokeName(string memory _name) public {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        if (nameLookup[name] == 0) revert Unregistered();
        IClusters.PriceIntegral memory integral = priceIntegral[name];
        (uint256 spent, uint256 newPrice) = pricing.getIntegratedPrice(
            integral.lastUpdatedPrice,
            block.timestamp - integral.lastUpdatedTimestamp,
            block.timestamp - integral.lastUpdatedTimestamp
        );
        // If out of backing (expired), transfer to highest sufficient bidder or delete registration
        uint256 backing = ethBacking[name];
        if (spent >= backing) {
            delete ethBacking[name];
            unchecked {
                protocolRevenue += backing;
            }
            // If there is a valid bid, transfer to the bidder
            address bidder;
            uint256 bid = bids[name].ethAmount;
            if (bid > 0) {
                bidder = bids[name].bidder;
                unchecked {
                    ethBacking[name] += bid;
                }
                delete bids[name];
            }
            // If there isn't a highest bidder, name will expire and be deleted as bidder is address(0)
            _transferName(name, nameLookup[name], addressLookup[bidder]);
        } else {
            // Process price data update
            unchecked {
                protocolRevenue += spent;
                ethBacking[name] -= spent;
            }
            priceIntegral[name] = IClusters.PriceIntegral({
                name: name,
                lastUpdatedTimestamp: block.timestamp,
                lastUpdatedPrice: newPrice,
                maxExpiry: 0 // TODO: Correct this value
            });
            emit PokeName(_name, msg.sender);
        }
    }

    /// @notice Place bids on valid names. Subsequent calls increases existing bid. If name is expired update ownership.
    ///         All bids timelocked for 30 days, unless they are outbid in which they are returned. Increasing a bid
    ///         resets the timelock.
    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(string memory _name) external payable checkPrivileges("") {
        bytes32 name = _toBytes32(_name);
        if (name == bytes32("")) revert Invalid();
        if (msg.value == 0) revert NoBid();
        uint256 clusterId = nameLookup[name];
        if (clusterId == 0) revert Unregistered();
        // Prevent name owner from bidding on their own name
        if (clusterId == addressLookup[msg.sender]) revert SelfBid();
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = bids[name].ethAmount;
        address prevBidder = bids[name].bidder;
        // Revert if bid isn't sufficient or greater than the highest bid, bypass for highest bidder
        if (prevBidder != msg.sender && (msg.value <= prevBid || msg.value < pricing.minAnnualPrice())) {
            revert Insufficient();
        }
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        else if (prevBidder == msg.sender) {
            unchecked {
                bids[name].ethAmount += msg.value;
            }
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[name].createdTimestamp = block.timestamp;
            emit BidIncreased(_name, msg.sender, prevBid + msg.value);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            bids[name] = IClusters.Bid(msg.value, block.timestamp, msg.sender);
            emit BidPlaced(_name, msg.sender, msg.value);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(prevBidder).call{value: prevBid}("");
                if (!success) bidRefunds[prevBidder] += prevBid;
                else emit BidRefunded(_name, prevBidder, msg.value);
            }
        }
        // Update name status and transfer to highest bidder if expired
        pokeName(_name);
    }

    /// @notice Reduce bid and refund difference. Revoke if _amount is the total bid or is the max uint256 value.
    function reduceBid(string memory _name, uint256 _amount) external {
        bytes32 name = _toBytes32(_name);
        // Ensure the caller is the highest bidder
        if (bids[name].bidder != msg.sender) revert Unauthorized();

        // Prevent reducing or revoking a bid before the bid timelock is up
        if (block.timestamp < bids[name].createdTimestamp + BID_TIMELOCK) revert Timelock();

        // Poke name to update backing and ownership (if required) prior to bid adjustment
        pokeName(_name);

        // Calculate difference in unchecked block to allow underflow when using type(uint256).max
        uint256 bid = bids[name].ethAmount;
        uint256 diff;
        unchecked {
            diff = bid - _amount;
        }

        // Only process bid if it's still present after the poke, which implies name wasn't transferred
        if (bid == 0) revert NoBid();
        // Revert if _amount is larger than the bid but isn't the max
        // Bypassing this check for the max value eliminates the need for the frontend or bidder to find their bid prior
        if (_amount > bid && _amount != type(uint256).max) revert Insufficient();
        // Also revert if bid is reduced beneath minimum annual price
        if (diff != 0 && diff < pricing.minAnnualPrice()) revert Insufficient();

        // If reducing bid to 0 or by maximum uint256 value, revoke altogether
        if (diff == 0 || _amount == type(uint256).max) {
            delete bids[name];
            emit BidRevoked(_name, msg.sender, bid);
        }
        // Otherwise, decrease bid and update timestamp
        else {
            unchecked {
                bids[name].ethAmount -= _amount;
            }
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[name].createdTimestamp = block.timestamp;
            emit BidReduced(_name, msg.sender, _amount);
        }
        // Overwrite type(uint256).max with bid so transfer doesn't fail
        if (_amount == type(uint256).max) _amount = bid;
        // Transfer bid reduction after all state is purged to prevent reentrancy
        // This bid refund reverts upon failure because it isn't happening in a forced context such as being outbid
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    // TODO: implementation
    function acceptBid(string memory _name) external returns (uint256) {}

    /// @notice Allow failed bid refunds to be withdrawn
    function refundBid() external {
        uint256 refund = bidRefunds[msg.sender];
        if (refund == 0) revert NoBid();
        delete bidRefunds[msg.sender];
        (bool success,) = payable(msg.sender).call{value: refund}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    /// LOCAL NAME MANAGEMENT ///

    /// @notice Set canonical name or erase it by setting ""
    function setCanonicalName(string memory _name) external checkPrivileges(_name) {
        bytes32 name = _toBytes32(_name);
        uint256 clusterId = addressLookup[msg.sender];
        if (bytes(_name).length == 0) {
            delete canonicalClusterName[clusterId];
            emit CanonicalName("", clusterId);
        } else {
            canonicalClusterName[clusterId] = name;
            emit CanonicalName(_name, clusterId);
        }
    }

    /// @notice Set wallet name for msg.sender or erase it by setting ""
    function setWalletName(address _addr, string memory _walletName) external checkPrivileges("") {
        bytes32 walletName = _toBytes32(_walletName);
        uint256 clusterId = addressLookup[msg.sender];
        if (clusterId != addressLookup[_addr]) revert Unauthorized();
        if (bytes(_walletName).length == 0) {
            walletName = reverseLookup[_addr];
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[_addr];
            emit WalletName("", _addr);
        } else {
            forwardLookup[clusterId][walletName] = _addr;
            reverseLookup[_addr] = walletName;
            emit WalletName(_walletName, _addr);
        }
    }

    /// @dev Set name-related state variables
    function _assignName(bytes32 name, uint256 clusterId) internal {
        nameLookup[name] = clusterId;
        _clusterNames[clusterId].add(name);
    }

    /// @dev Purge name-related state variables
    function _unassignName(bytes32 name, uint256 clusterId) internal {
        nameLookup[name] = 0;
        if (canonicalClusterName[clusterId] == name) {
            delete canonicalClusterName[clusterId];
            emit CanonicalName("", clusterId);
        }
        _clusterNames[clusterId].remove(name);
    }

    /// STRING HELPERS ///

    /// @dev Returns bytes32 representation of string < 32 characters, used in name-related state vars and functions
    function _toBytes32(string memory _smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(_smallString);
        if (smallBytes.length > 32) revert Invalid();
        return bytes32(smallBytes);
    }

    /// @dev Returns a string from a small bytes32 string.
    function _toString(bytes32 _smallBytes) internal pure returns (string memory result) {
        if (_smallBytes == bytes32("")) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, _smallBytes)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, _smallBytes)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }
}
