// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {IPricing} from "./IPricing.sol";

import {IClusters} from "./IClusters.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
abstract contract NameManager is IClusters {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 internal constant BID_TIMELOCK = 30 days;

    IPricing internal pricing;

    uint256 public nextClusterId = 1;

    /// @notice Which cluster an address belongs to
    mapping(address addr => uint256 clusterId) public addressToClusterId;

    /// @notice Which cluster a name belongs to
    mapping(bytes32 name => uint256 clusterId) public nameToClusterId;

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

    /// @notice The amount of money backing each name registration
    mapping(bytes32 name => uint256 amount) public nameBacking;

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(bytes32 name => IClusters.Bid bidData) public bids;

    /// @notice Failed bid refunds are pooled so we don't have to revert when the highest bid is outbid
    mapping(address bidder => uint256 refund) public bidRefunds;

    /**
     * PROTOCOL INVARIANT TRACKING
     * address(this).balance >= protocolRevenue + totalNameBacking + totalBidBacking
     */

    /// @notice Amount of eth that's transferred from nameBacking to the protocol
    uint256 public protocolRevenue;

    /// @notice Amount of eth that's backing names
    uint256 public totalNameBacking;

    /// @notice Amount of eth that's sitting in active bids and canceled but not-yet-withdrawn bids
    uint256 public totalBidBacking;

    /// @dev Used to prevent multicallable functions from being called outside of the context of multicall()
    bool internal _inMulticall;

    /// @dev Ensure value isn't less than minimum annual price and is covered by msg.value
    function _checkValue(uint256 value) internal view {
        if (value > msg.value) revert Insufficient();
    }

    /// @dev Ensure name is valid (not empty or too long)
    function _checkNameValid(string memory name) internal pure {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(name).length > 32) revert LongName();
    }

    /// @dev Ensure addr has a cluster
    function _checkZeroCluster(address addr) internal view {
        if (addressToClusterId[addr] == 0) revert NoCluster();
    }

    /// @dev Ensure addr owns name, make sure you always check name and cluster validity before this function!
    function _checkNameOwnership(address addr, string memory name) internal view {
        // Short circuit if name is empty and caller has cluster to allow resets
        // This is why name and cluster validity must be checked before using this
        if (addressToClusterId[addr] != 0 && bytes(name).length == 0) return;
        if (addressToClusterId[addr] != nameToClusterId[_toBytes32(name)]) revert Unauthorized();
    }

    /// @notice Prevents modified functions from being callable outside of the context of multicall()
    modifier onlyMulticall() {
        if (!_inMulticall) revert MulticallFailed();
        _;
    }

    /// @notice Prevents modified functions from being called inside of the context of a multicall()
    modifier noMulticall() {
        if (_inMulticall) revert MulticallFailed();
        _;
    }

    constructor(address pricing_) {
        pricing = IPricing(pricing_);
    }

    /// VIEW FUNCTIONS ///

    /// @notice Get all names owned by a cluster in bytes32 format
    /// @return names Array of names in bytes32 format
    function getClusterNamesBytes32(uint256 clusterId) external view returns (bytes32[] memory names) {
        return _clusterNames[clusterId].values();
    }

    /// @notice Get all names owned by a cluster in string format
    /// @dev Do not use this onchain as it is a denial-of-service vector due to loop potentially exceeding gas ceiling
    /// @return names Array of names in string format
    function getClusterNamesString(uint256 clusterId) external view returns (string[] memory names) {
        bytes32[] memory namesBytes32 = _clusterNames[clusterId].values();
        names = new string[](namesBytes32.length);
        for (uint256 i; i < namesBytes32.length;) {
            names[i] = _toString(namesBytes32[i]);
        }
    }

    /// @notice Get Bid struct from storage
    /// @return bid Bid struct
    function getBid(bytes32 name) external view returns (IClusters.Bid memory bid) {
        return bids[name];
    }

    /// ECONOMIC FUNCTIONS ///

    /// @notice Buy unregistered name. Must pay at least minimum yearly payment.
    function buyName(string memory name) external payable noMulticall {
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = addressToClusterId[msg.sender];
        // Check that name is unused and sufficient payment is made
        if (nameToClusterId[_name] != 0) revert Registered();
        if (msg.value < pricing.minAnnualPrice()) revert Insufficient();
        // Process price accounting updates
        nameBacking[_name] += msg.value;
        totalNameBacking += msg.value;
        priceIntegral[_name] = IClusters.PriceIntegral({
            name: _name,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice()
        });
        _assignName(_name, clusterId);
        emit BuyName(name, clusterId);
    }

    /// @notice Fund an existing and specific name, callable by anyone
    function fundName(string memory name) external payable noMulticall {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        if (nameToClusterId[_name] == 0) revert Unregistered();
        nameBacking[_name] += msg.value;
        totalNameBacking += msg.value;
        emit FundName(name, msg.sender, msg.value);
    }

    /// @notice Move name from one cluster to another without payment
    function transferName(string memory name, uint256 toClusterId) public {
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        _checkNameOwnership(msg.sender, name);
        bytes32 _name = _toBytes32(name);
        if (toClusterId >= nextClusterId) revert Unregistered();
        uint256 clusterId = addressToClusterId[msg.sender];
        _transferName(_name, clusterId, toClusterId);
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
            // Assign name to new cluster, _unassignName() isn't used because it resets nameToClusterId
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
    function pokeName(string memory name) public {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        if (nameToClusterId[_name] == 0) revert Unregistered();
        IClusters.PriceIntegral memory integral = priceIntegral[_name];
        (uint256 spent, uint256 newPrice) = pricing.getIntegratedPrice(
            integral.lastUpdatedPrice,
            block.timestamp - integral.lastUpdatedTimestamp,
            block.timestamp - integral.lastUpdatedTimestamp
        );
        // If out of backing (expired), transfer to highest sufficient bidder or delete registration
        uint256 backing = nameBacking[_name];
        if (spent >= backing) {
            delete nameBacking[_name];
            totalNameBacking -= backing;
            protocolRevenue += backing;
            // If there is a valid bid, transfer to the bidder
            address bidder;
            uint256 bid = bids[_name].ethAmount;
            if (bid > 0) {
                bidder = bids[_name].bidder;
                nameBacking[_name] += bid;
                totalNameBacking += bid;
                delete bids[_name];
            }
            // If there isn't a highest bidder, name will expire and be deleted as bidder is address(0)
            _transferName(_name, nameToClusterId[_name], addressToClusterId[bidder]);
        } else {
            // Process price data update
            nameBacking[_name] -= spent;
            totalNameBacking -= spent;
            protocolRevenue += spent;
            priceIntegral[_name] = IClusters.PriceIntegral({
                name: _name,
                lastUpdatedTimestamp: block.timestamp,
                lastUpdatedPrice: newPrice
            });
            emit PokeName(name, msg.sender);
        }
    }

    /// @notice Place bids on valid names. Subsequent calls increases existing bid. If name is expired update ownership.
    ///         All bids timelocked for 30 days, unless they are outbid in which they are returned. Increasing a bid
    ///         resets the timelock.
    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    function bidName(string memory name) external payable noMulticall {
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        if (msg.value == 0) revert NoBid();
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = nameToClusterId[_name];
        if (clusterId == 0) revert Unregistered();
        // Prevent name owner from bidding on their own name
        if (clusterId == addressToClusterId[msg.sender]) revert SelfBid();
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = bids[_name].ethAmount;
        address prevBidder = bids[_name].bidder;
        // Revert if bid isn't sufficient or greater than the highest bid, bypass for highest bidder
        if (prevBidder != msg.sender && (msg.value <= prevBid || msg.value < pricing.minAnnualPrice())) {
            revert Insufficient();
        }
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        else if (prevBidder == msg.sender) {
            bids[_name].ethAmount += msg.value;
            totalBidBacking += msg.value;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidIncreased(name, msg.sender, prevBid + msg.value);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            bids[_name] = IClusters.Bid(msg.value, block.timestamp, msg.sender);
            totalBidBacking += msg.value;
            emit BidPlaced(name, msg.sender, msg.value);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(prevBidder).call{value: prevBid}("");
                if (!success) {
                    bidRefunds[prevBidder] += prevBid;
                } else {
                    totalBidBacking -= prevBid;
                    emit BidRefunded(name, prevBidder, msg.value);
                }
            }
        }
        // Update name status and transfer to highest bidder if expired
        pokeName(name);
    }

    /// @notice Reduce bid and refund difference. Revoke if amount is the total bid or is the max uint256 value.
    function reduceBid(string memory name, uint256 amount) public {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        uint256 bid = bids[_name].ethAmount;
        if (bid == 0) revert NoBid();
        if (bids[_name].bidder != msg.sender) revert Unauthorized();
        // Prevent reducing or revoking a bid before the bid timelock is up
        if (block.timestamp < bids[_name].createdTimestamp + BID_TIMELOCK) revert Timelock();
        // Overwrite amount with total bid in assumption caller is revoking bid
        if (amount > bid) amount = bid;

        // Poke name to update backing and ownership (if required) prior to bid adjustment
        pokeName(name);
        // Short circuit if pokeName() processed transfer to bidder due to name expiry
        if (bids[_name].ethAmount == 0) return;

        // Revert if reduction will push bid beneath minAnnualPrice
        uint256 diff = bid - amount;
        if (diff != 0 && diff < pricing.minAnnualPrice()) revert Insufficient();

        // If reducing bid to 0 or by maximum uint256 value, revoke altogether
        if (diff == 0) {
            delete bids[_name];
            totalBidBacking -= bid;
            emit BidRevoked(name, msg.sender, bid);
        }
        // Otherwise, decrease bid and update timestamp
        else {
            bids[_name].ethAmount -= amount;
            totalBidBacking -= amount;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidReduced(name, msg.sender, amount);
        }

        // Transfer bid reduction after all state is purged to prevent reentrancy
        // This bid refund reverts upon failure because it isn't happening in a forced context such as being outbid
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    /// @notice Accept bid and transfer name to bidder
    /// @dev Retrieves bid, adjusts state, then sends payment to avoid reentrancy
    function acceptBid(string memory name) public returns (uint256 bidAmount) {
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        _checkNameOwnership(msg.sender, name);
        bytes32 _name = _toBytes32(name);
        Bid memory bid = bids[_name];
        if (bid.ethAmount == 0) revert NoBid();
        delete bids[_name];
        totalBidBacking -= bid.ethAmount;
        _transferName(_name, nameToClusterId[_name], addressToClusterId[bid.bidder]);
        (bool success,) = payable(msg.sender).call{value: bid.ethAmount}("");
        if (!success) revert NativeTokenTransferFailed();
        return bid.ethAmount;
    }

    /// @notice Allow failed bid refunds to be withdrawn
    function refundBid() public {
        uint256 refund = bidRefunds[msg.sender];
        if (refund == 0) revert NoBid();
        delete bidRefunds[msg.sender];
        totalBidBacking -= refund;
        (bool success,) = payable(msg.sender).call{value: refund}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    /// LOCAL NAME MANAGEMENT ///

    /// @notice Set canonical name or erase it by setting ""
    function setCanonicalName(string memory name) public {
        if (bytes(name).length > 32) revert LongName();
        _checkZeroCluster(msg.sender);
        _checkNameOwnership(msg.sender, name);
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = addressToClusterId[msg.sender];
        if (bytes(name).length == 0) {
            delete canonicalClusterName[clusterId];
            emit CanonicalName("", clusterId);
        } else {
            canonicalClusterName[clusterId] = _name;
            emit CanonicalName(name, clusterId);
        }
    }

    /// @notice Set wallet name for msg.sender or erase it by setting ""
    function setWalletName(address addr, string memory walletName) public {
        if (bytes(walletName).length > 32) revert LongName();
        _checkZeroCluster(msg.sender);
        bytes32 _walletName = _toBytes32(walletName);
        uint256 clusterId = addressToClusterId[msg.sender];
        if (clusterId != addressToClusterId[addr]) revert Unauthorized();
        if (bytes(walletName).length == 0) {
            _walletName = reverseLookup[addr];
            delete forwardLookup[clusterId][_walletName];
            delete reverseLookup[addr];
            emit WalletName("", addr);
        } else {
            forwardLookup[clusterId][_walletName] = addr;
            reverseLookup[addr] = _walletName;
            emit WalletName(walletName, addr);
        }
    }

    /// @dev Set name-related state variables
    function _assignName(bytes32 name, uint256 clusterId) internal {
        nameToClusterId[name] = clusterId;
        _clusterNames[clusterId].add(name);
    }

    /// @dev Purge name-related state variables
    function _unassignName(bytes32 name, uint256 clusterId) internal {
        nameToClusterId[name] = 0;
        if (canonicalClusterName[clusterId] == name) {
            delete canonicalClusterName[clusterId];
            emit CanonicalName("", clusterId);
        }
        _clusterNames[clusterId].remove(name);
    }

    /// STRING HELPERS ///

    /// @dev Returns bytes32 representation of string < 32 characters, used in name-related state vars and functions
    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        if (smallBytes.length > 32) revert LongName();
        return bytes32(smallBytes);
    }

    /// @dev Returns a string from a right-padded bytes32 representation.
    function _toString(bytes32 smallBytes) internal pure returns (string memory result) {
        if (smallBytes == bytes32("")) return result;
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

    /// MULTICALL FUNCTIONS ///

    /// @notice buyName() override for use in multicall() only
    function buyName(uint256 value, string memory name) external payable onlyMulticall {
        _checkValue(value);
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = addressToClusterId[msg.sender];
        // Check that name is unused and sufficient payment is made
        if (nameToClusterId[_name] != 0) revert Registered();
        if (value < pricing.minAnnualPrice()) revert Insufficient();
        // Process price accounting updates
        nameBacking[_name] += value;
        totalNameBacking += value;
        priceIntegral[_name] = IClusters.PriceIntegral({
            name: _name,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice()
        });
        _assignName(_name, clusterId);
        emit BuyName(name, clusterId);
    }

    /// @notice fundName() override for use in multicall() only
    function fundName(uint256 value, string memory name) external payable onlyMulticall {
        _checkValue(value);
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        if (nameToClusterId[_name] == 0) revert Unregistered();
        nameBacking[_name] += value;
        totalNameBacking += value;
        emit FundName(name, msg.sender, value);
    }

    /// @notice transferName() override used in payable multicalls
    function transferName(uint256, string memory name, uint256 toClusterId) external payable onlyMulticall {
        transferName(name, toClusterId);
    }

    /// @notice pokeName() override used in payable multicalls
    function pokeName(uint256, string memory name) external payable onlyMulticall {
        pokeName(name);
    }

    /// @notice bidName() override for use in multicall() only
    function bidName(uint256 value, string memory name) external payable onlyMulticall {
        _checkValue(value);
        _checkNameValid(name);
        _checkZeroCluster(msg.sender);
        if (value == 0) revert NoBid();
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = nameToClusterId[_name];
        if (clusterId == 0) revert Unregistered();
        // Prevent name owner from bidding on their own name
        if (clusterId == addressToClusterId[msg.sender]) revert SelfBid();
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = bids[_name].ethAmount;
        address prevBidder = bids[_name].bidder;
        // Revert if bid isn't sufficient or greater than the highest bid, bypass for highest bidder
        if (prevBidder != msg.sender && (value <= prevBid || value < pricing.minAnnualPrice())) {
            revert Insufficient();
        }
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        else if (prevBidder == msg.sender) {
            bids[_name].ethAmount += value;
            totalBidBacking += value;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidIncreased(name, msg.sender, prevBid + value);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            bids[_name] = IClusters.Bid(value, block.timestamp, msg.sender);
            totalBidBacking += value;
            emit BidPlaced(name, msg.sender, value);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(prevBidder).call{value: prevBid}("");
                if (!success) {
                    bidRefunds[prevBidder] += prevBid;
                } else {
                    totalBidBacking -= prevBid;
                    emit BidRefunded(name, prevBidder, value);
                }
            }
        }
        // Update name status and transfer to highest bidder if expired
        pokeName(name);
    }

    /// @notice reduceBid() override used in payable multicalls
    function reduceBid(uint256, string memory name, uint256 amount) external payable onlyMulticall {
        reduceBid(name, amount);
    }

    /// @notice acceptBid() override used in payable multicalls
    function acceptBid(uint256, string memory name) external payable onlyMulticall returns (uint256 bidAmount) {
        return acceptBid(name);
    }

    /// @notice refundBid() override used in payable multicalls
    function refundBid(uint256) external payable onlyMulticall {
        refundBid();
    }

    /// @notice setCanonicalName() override used in payable multicalls
    function setCanonicalName(uint256, string memory name) external payable onlyMulticall {
        return setCanonicalName(name);
    }

    /// @notice setWalletName() override used in payable multicalls
    function setWalletName(uint256, address addr, string memory walletName) external payable onlyMulticall {
        return setWalletName(addr, walletName);
    }
}
