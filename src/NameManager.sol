// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSetLib} from "./EnumerableSetLib.sol";

import {IPricing} from "./IPricing.sol";

import {IClusters} from "./IClusters.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
abstract contract NameManager is IClusters {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    struct NameData {
        /// @notice Which cluster a name belongs to
        uint96 clusterId;
        /// @notice The amount of money backing each name registration
        uint96 backing;
        /// @notice Data required for proper harberger tax calculation when pokeName() is called
        IClusters.PriceIntegral integral;
        uint256 integralPacked;
        /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
        IClusters.Bid bid;
    }

    address public immutable endpoint;

    uint256 internal immutable marketOpenTimestamp;

    uint256 internal constant BID_TIMELOCK = 30 days;

    IPricing internal pricing;

    /// @notice Which cluster an address belongs to
    mapping(bytes32 addr => uint256 clusterId) public addressToClusterId;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => bytes32 name) public defaultClusterName;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSetLib.Bytes32Set names) internal _clusterNames;

    /// @notice For example lookup[17]["hot"] -> 0x123...
    mapping(uint256 clusterId => mapping(bytes32 walletName => bytes32 addr)) public forwardLookup;

    /// @notice For example lookup[0x123...] -> "hot", then combine with cluster name in a diff method
    mapping(bytes32 addr => bytes32 walletName) public reverseLookup;

    mapping(bytes32 name => NameData) internal _nameData;

    /// @notice Failed bid refunds are pooled so we don't have to revert when the highest bid is outbid
    mapping(bytes32 bidder => uint256 refund) public bidRefunds;

    /**
     * PROTOCOL INVARIANT TRACKING
     * address(this).balance >= protocolRevenue + totalNameBacking + totalBidBacking
     */

    /// @notice Amount of eth that's transferred from nameBacking to the protocol
    uint96 internal _protocolRevenue;

    /// @notice Amount of eth that's sitting in active bids and canceled but not-yet-withdrawn bids
    uint96 internal _totalBidBacking;

    /// @notice Amount of eth that's backing names
    uint96 internal _totalNameBacking;

    /// @dev Ensures balance invariant holds
    function _checkInvariant() internal view {
        unchecked {
            if (
                address(this).balance
                    < uint256(_protocolRevenue) + uint256(_totalNameBacking) + uint256(_totalBidBacking)
            ) {
                revert BadInvariant();
            }
        }
    }

    /// @dev Ensure name is valid (not empty or too long)
    function _checkNameValid(string memory name) internal pure {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(name).length > 32) revert LongName();
    }

    /// @dev Ensure addr owns name
    function _checkNameOwnership(bytes32 addr, string memory name) internal view {
        if (addressToClusterId[addr] != 0) revert NoCluster();
        if (bytes(name).length == 0) return; // Short circuit for reset as cluster addresses never own name ""
        if (addressToClusterId[addr] != _nameData[_toBytes32(name)].clusterId) revert Unauthorized();
    }

    /// @dev Ensure addr has a cluster
    function _fixZeroCluster(bytes32 addr) internal {
        if (addressToClusterId[addr] == 0) _hookCreate(addr);
    }

    /// @dev Hook used to access _add() from Clusters.sol to abstract away cluster creation
    function _hookCreate(bytes32 msgSender) internal virtual;

    /// @dev Hook used to access clusterAddresses() from Clusters.sol to delete clusters if all names are removed
    function _hookDelete(uint256 clusterId) internal virtual;

    /// @dev Hook used to access cluster's _verifiedAddresses length to confirm cluster is valid before name transfer
    function _hookCheck(uint256 clusterId) internal virtual;

    function protocolRevenue() public view returns (uint256) {
        return uint256(_protocolRevenue);
    }

    function totalBidBacking() public view returns (uint256) {
        return uint256(_totalBidBacking);
    }

    function totalNameBacking() public view returns (uint256) {
        return uint256(_totalNameBacking);
    }

    function nameToClusterId(bytes32 name) public view returns (uint256) {
        return uint256(_nameData[name].clusterId);
    }

    function bids(bytes32 name) public view returns (uint256, uint256, bytes32) {
        IClusters.Bid memory bid = _nameData[name].bid;
        return (uint256(bid.ethAmount), uint256(bid.createdTimestamp), bytes32(bid.bidder));
    }

    function priceIntegral(bytes32 name) public view returns (bytes32, uint256, uint256) {
        IClusters.PriceIntegral memory integral = _nameData[name].integral;
        return (bytes32(integral.name), uint256(integral.lastUpdatedTimestamp), uint256(integral.lastUpdatedPrice));
    }

    function nameBacking(bytes32 name) public view returns (uint256) {
        return uint256(_nameData[name].backing);
    }

    /// @notice Used to restrict external functions to
    modifier onlyEndpoint(bytes32 msgSender) {
        if (_addressToBytes(msg.sender) != msgSender && msg.sender != endpoint) revert Unauthorized();
        _;
    }

    constructor(address pricing_, address endpoint_, uint256 marketOpenTimestamp_) {
        if (marketOpenTimestamp_ < block.timestamp) revert Invalid();
        pricing = IPricing(pricing_);
        endpoint = endpoint_;
        marketOpenTimestamp = marketOpenTimestamp_;
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
        return _nameData[name].bid;
    }

    /// ECONOMIC FUNCTIONS ///

    /// @notice Buy unregistered name. Must pay at least minimum yearly payment.
    /// @dev Processing is handled in overload
    function buyName(uint256 msgValue, string memory name) external payable {
        bytes32 msgSender = _addressToBytes(msg.sender);
        buyName(msgSender, msgValue, name);
    }

    /// @notice buyName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) public payable onlyEndpoint(msgSender) {
        // Only allow initial buys to come from endpoint to enforce an initial temporarily frontend controlled market
        if (block.timestamp < marketOpenTimestamp && msg.sender != endpoint) revert Unauthorized();
        _checkNameValid(name);
        _fixZeroCluster(msgSender);
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        uint256 clusterId = addressToClusterId[msgSender];
        // Check that name is unused and sufficient payment is made
        if (nameData.clusterId != 0) revert Registered();
        if (msgValue < pricing.minAnnualPrice()) revert Insufficient();
        // Process price accounting updates
        nameData.backing += uint96(msgValue);
        _totalNameBacking += uint96(msgValue);
        _setIntegral(nameData, _name, pricing.minAnnualPrice());
        _assignName(_name, clusterId);
        if (defaultClusterName[clusterId] == bytes32("")) defaultClusterName[clusterId] = _name;
        emit BuyName(_name, clusterId, msgValue);

        _checkInvariant();
    }

    /// @notice Fund an existing and specific name, callable by anyone
    /// @dev Processing is handled in overload
    function fundName(uint256 msgValue, string memory name) external payable {
        fundName(_addressToBytes(msg.sender), msgValue, name);
    }

    /// @notice fundName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function fundName(bytes32 msgSender, uint256 msgValue, string memory name) public payable onlyEndpoint(msgSender) {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        if (nameData.clusterId == 0) revert Unregistered();
        nameData.backing += uint96(msgValue);
        _totalNameBacking += uint96(msgValue);
        emit FundName(_name, msgSender, msgValue);

        _checkInvariant();
    }

    /// @notice Move name from one cluster to another without payment
    /// @dev Processing is handled in overload
    function transferName(string memory name, uint256 toClusterId) external payable {
        transferName(_addressToBytes(msg.sender), name, toClusterId);
    }

    /// @notice transferName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function transferName(bytes32 msgSender, string memory name, uint256 toClusterId)
        public
        payable
        onlyEndpoint(msgSender)
    {
        _checkNameValid(name);
        _checkNameOwnership(msgSender, name);
        bytes32 _name = _toBytes32(name);
        uint256 fromClusterId = addressToClusterId[msgSender];
        // Prevent transfers to empty/invalid clusters
        _hookCheck(toClusterId);
        _transferName(_name, fromClusterId, toClusterId);
    }

    /// @dev Transfer cluster name or delete cluster name without checking auth
    /// @dev Delete by transferring to cluster id 0
    function _transferName(bytes32 name, uint256 fromClusterId, uint256 toClusterId) internal {
        // If name is canonical cluster name for sending cluster, remove that assignment
        if (defaultClusterName[fromClusterId] == name) {
            delete defaultClusterName[fromClusterId];
        }
        // Assign name to new cluster, otherwise unassign
        if (toClusterId != 0) {
            // Assign name to new cluster, _unassignName() isn't used because it resets nameToClusterId
            _assignName(name, toClusterId);
            _clusterNames[fromClusterId].remove(name);
        } else {
            // Purge name assignment and remove from cluster
            _unassignName(name, fromClusterId);
        }
        emit TransferName(name, fromClusterId, toClusterId);
        // Purge all addresses from cluster if last name was transferred out
        if (_clusterNames[fromClusterId].length() == 0) _hookDelete(fromClusterId);
    }

    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and transfer names upon expiry to highest
    ///         sufficient bidder. If no bids above yearly minimum, delete name registration.
    function pokeName(string memory name) public payable {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        if (nameData.clusterId == 0) revert Unregistered();
        IClusters.PriceIntegral memory integral = _getIntegral(nameData);
        (uint256 spent, uint256 newPrice) = pricing.getIntegratedPrice(
            integral.lastUpdatedPrice,
            block.timestamp - integral.lastUpdatedTimestamp,
            block.timestamp - integral.lastUpdatedTimestamp // TOOD: this isn't accurate, but we're not tracking
                // creation time atm. Need to do that or relax pricing algo params
        );
        // If out of backing (expired), transfer to highest sufficient bidder or delete registration
        uint256 backing = uint256(nameData.backing);
        if (spent >= backing) {
            delete nameData.backing;
            _totalNameBacking -= uint96(backing);
            _protocolRevenue += uint96(backing);
            // If there is a valid bid, transfer to the bidder
            bytes32 bidder;
            uint256 bid = nameData.bid.ethAmount;
            if (bid > 0) {
                bidder = nameData.bid.bidder;
                nameData.backing += uint96(bid);
                _totalNameBacking += uint96(bid);
                delete nameData.bid;
            }
            // If there isn't a highest bidder, name will expire and be deleted as bidder is bytes32(0)
            _transferName(_name, nameData.clusterId, addressToClusterId[bidder]);
        } else {
            // Process price data update
            nameData.backing -= uint96(spent);
            _totalNameBacking -= uint96(spent);
            _protocolRevenue += uint96(spent);
            _setIntegral(nameData, _name, newPrice);
            emit PokeName(_name);
        }
    }

    function _setIntegral(NameData storage nameData, bytes32 name_, uint256 lastUpdatedPrice) internal {
        bytes32 truncatedName = bytes32(bytes20(name_));
        if (truncatedName == name_) {
            if (block.timestamp <= 0xffffffff) {
                if (lastUpdatedPrice <= 0xffffffffffffffff) {
                    nameData.integralPacked = uint256(truncatedName) | (block.timestamp << 64) | lastUpdatedPrice;
                    return;
                }
            }
        }
        nameData.integralPacked = 0;
        nameData.integral = IClusters.PriceIntegral({
            name: name_,
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: lastUpdatedPrice
        });
    }

    function _getIntegral(NameData storage nameData) internal view returns (IClusters.PriceIntegral memory integral) {
        uint256 integralPacked = nameData.integralPacked;
        if (integralPacked == 0) {
            integral = nameData.integral;
        } else {
            integral.name = bytes32((integralPacked >> 96) << 96);
            integral.lastUpdatedTimestamp = (integralPacked >> 64) & 0xffffffff;
            integral.lastUpdatedPrice = integralPacked & 0xffffffffffffffff;
        }
    }

    /// @notice Place bids on valid names. Subsequent calls increases existing bid. If name is expired update ownership.
    ///         All bids timelocked for 30 days, unless they are outbid in which they are returned. Increasing a bid
    ///         resets the timelock.
    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    /// @dev Processing is handled in overload
    function bidName(uint256 msgValue, string memory name) external payable {
        bidName(_addressToBytes(msg.sender), msgValue, name);
    }

    /// @notice bidName() overload used in endpoint, msgSender must be msg.sender or endpoint
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name) public payable onlyEndpoint(msgSender) {
        _checkNameValid(name);
        if (msgValue == 0) revert NoBid();
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        uint256 clusterId = nameData.clusterId;
        if (clusterId == 0) revert Unregistered();
        // Prevent name owner from bidding on their own name
        if (clusterId == addressToClusterId[msgSender]) revert SelfBid();
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = nameData.bid.ethAmount;
        bytes32 prevBidder = nameData.bid.bidder;
        // Revert if bid isn't sufficient or greater than the highest bid, bypass for highest bidder
        if (prevBidder != msgSender && (msgValue <= prevBid || msgValue < pricing.minAnnualPrice())) {
            revert Insufficient();
        }
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        else if (prevBidder == msgSender) {
            nameData.bid.ethAmount += msgValue;
            _totalBidBacking += uint96(msgValue);
            // TODO: Determine which way is best to handle bid update timestamps
            // nameData.bid.createdTimestamp = block.timestamp;
            emit BidIncreased(_name, msgSender, prevBid + msgValue);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            nameData.bid = IClusters.Bid(msgValue, block.timestamp, msgSender);
            _totalBidBacking += uint96(msgValue);
            emit BidPlaced(_name, msgSender, msgValue);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(_bytesToAddress(prevBidder)).call{value: prevBid}("");
                if (!success) {
                    bidRefunds[prevBidder] += prevBid;
                } else {
                    _totalBidBacking -= uint96(prevBid);
                    emit BidRefunded(_name, prevBidder, msgValue);
                }
            }
        }
        // Update name status and transfer to highest bidder if expired
        pokeName(name);

        _checkInvariant();
    }

    /// @notice Reduce bid and refund difference. Revoke if amount is the total bid or is the max uint256 value.
    /// @dev Processing is handled in overload
    function reduceBid(string memory name, uint256 amount) external payable {
        reduceBid(_addressToBytes(msg.sender), name, amount);
    }

    /// @notice reduceBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function reduceBid(bytes32 msgSender, string memory name, uint256 amount) public payable onlyEndpoint(msgSender) {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        uint256 bid = nameData.bid.ethAmount;
        if (bid == 0) revert NoBid();
        if (nameData.bid.bidder != msgSender) revert Unauthorized();
        // Prevent reducing or revoking a bid before the bid timelock is up
        if (block.timestamp < nameData.bid.createdTimestamp + BID_TIMELOCK) revert Timelock();
        // Overwrite amount with total bid in assumption caller is revoking bid
        if (amount > bid) amount = bid;

        // Poke name to update backing and ownership (if required) prior to bid adjustment
        pokeName(name);
        // Short circuit if pokeName() processed transfer to bidder due to name expiry
        if (nameData.bid.ethAmount == 0) return;

        // Revert if reduction will push bid beneath minAnnualPrice
        uint256 diff = bid - amount;
        if (diff != 0 && diff < pricing.minAnnualPrice()) revert Insufficient();

        // If reducing bid to 0 or by maximum uint256 value, revoke altogether
        if (diff == 0) {
            delete nameData.bid;
            _totalBidBacking -= uint96(bid);
            emit BidRevoked(_name, msgSender, bid);
        }
        // Otherwise, decrease bid and update timestamp
        else {
            nameData.bid.ethAmount -= amount;
            _totalBidBacking -= uint96(amount);
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidReduced(_name, msgSender, amount);
        }

        // Transfer bid reduction after all state is purged to prevent reentrancy
        // This bid refund reverts upon failure because it isn't happening in a forced context such as being outbid
        (bool success,) = payable(_bytesToAddress(msgSender)).call{value: amount}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    /// @notice Accept bid and transfer name to bidder
    /// @dev Retrieves bid, adjusts state, then sends payment to avoid reentrancy
    /// @dev Processing is handled in overload
    function acceptBid(string memory name) external payable returns (uint256 bidAmount) {
        return acceptBid(_addressToBytes(msg.sender), name);
    }

    /// @notice acceptBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function acceptBid(bytes32 msgSender, string memory name)
        public
        payable
        onlyEndpoint(msgSender)
        returns (uint256 bidAmount)
    {
        _checkNameValid(name);
        _checkNameOwnership(msgSender, name);
        bytes32 _name = _toBytes32(name);
        NameData storage nameData = _nameData[_name];
        Bid memory bid = nameData.bid;
        _fixZeroCluster(bid.bidder);
        if (bid.ethAmount == 0) revert NoBid();
        delete nameData.bid;
        _totalBidBacking -= uint96(bid.ethAmount);
        _transferName(_name, nameData.clusterId, addressToClusterId[bid.bidder]);
        (bool success,) = payable(_bytesToAddress(msgSender)).call{value: bid.ethAmount}("");
        if (!success) revert NativeTokenTransferFailed();
        return bid.ethAmount;
    }

    /// @notice Allow failed bid refunds to be withdrawn
    /// @dev No endpoint overload is provided as I don't see why someone would retry a failed bid refund via bridge
    function refundBid() external payable {
        refundBid(_addressToBytes(msg.sender));
    }

    /// @notice refundBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function refundBid(bytes32 msgSender) public payable onlyEndpoint(msgSender) {
        uint256 refund = bidRefunds[msgSender];
        if (refund == 0) revert NoBid();
        delete bidRefunds[msgSender];
        _totalBidBacking -= uint96(refund);
        (bool success,) = payable(_bytesToAddress(msgSender)).call{value: refund}("");
        if (!success) revert NativeTokenTransferFailed();
    }

    /// LOCAL NAME MANAGEMENT ///

    /// @notice Set canonical name or erase it by setting ""
    /// @dev Processing is handled in overload
    function setDefaultClusterName(string memory name) external payable {
        setDefaultClusterName(_addressToBytes(msg.sender), name);
    }

    /// @notice setDefaultClusterName() overload used by endpoint, msgSender must be msg.sender or endpoint.
    ///         It is not possible to remove a name from a cluster entirely. A cluster must always have its default name
    function setDefaultClusterName(bytes32 msgSender, string memory name) public payable onlyEndpoint(msgSender) {
        _checkNameValid(name);
        _checkNameOwnership(msgSender, name);
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = addressToClusterId[msgSender];
        defaultClusterName[clusterId] = _name;
        emit DefaultClusterName(_name, clusterId);
    }

    /// @notice Set wallet name for msg.sender or erase it by setting ""
    /// @dev Processing is handled in overload
    function setWalletName(bytes32 addr, string memory walletName) external payable {
        setWalletName(_addressToBytes(msg.sender), addr, walletName);
    }

    /// @notice setWalletName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function setWalletName(bytes32 msgSender, bytes32 addr, string memory walletName)
        public
        payable
        onlyEndpoint(msgSender)
    {
        uint256 clusterId = addressToClusterId[msgSender];
        if (clusterId != 0) revert NoCluster();
        if (bytes(walletName).length > 32) revert LongName();
        bytes32 _walletName = _toBytes32(walletName);
        if (clusterId != addressToClusterId[addr]) revert Unauthorized();
        if (bytes(walletName).length == 0) {
            _walletName = reverseLookup[addr];
            delete forwardLookup[clusterId][_walletName];
            delete reverseLookup[addr];
            emit SetWalletName(bytes32(""), addr);
        } else {
            bytes32 prev = forwardLookup[clusterId][_walletName];
            if (prev != bytes32("")) delete reverseLookup[prev];
            forwardLookup[clusterId][_walletName] = addr;
            reverseLookup[addr] = _walletName;
            emit SetWalletName(_walletName, addr);
        }
    }

    /// @dev Set name-related state variables
    function _assignName(bytes32 name, uint256 clusterId) internal {
        _nameData[name].clusterId = uint96(clusterId);
        _clusterNames[clusterId].add(name);
    }

    /// @dev Purge name-related state variables
    function _unassignName(bytes32 name, uint256 clusterId) internal {
        delete _nameData[name].clusterId;
        if (defaultClusterName[clusterId] == name) {
            delete defaultClusterName[clusterId];
            emit DefaultClusterName(bytes32(""), clusterId);
        }
        _clusterNames[clusterId].remove(name);
    }

    /// TYPE HELPERS ///

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

    /// @dev Returns bytes32 representation of address
    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @dev Returns address representation of bytes32
    function _bytesToAddress(bytes32 addr) internal pure returns (address) {
        return address(uint160(uint256(addr)));
    }
}
