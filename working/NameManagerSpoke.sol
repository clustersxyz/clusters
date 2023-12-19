// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSetLib} from "./EnumerableSetLib.sol";

import {IPricing} from "./interfaces/IPricing.sol";

import {IClusters} from "./interfaces/IClusters.sol";

import {IEndpoint} from "./interfaces/IEndpoint.sol";

import {console2} from "forge-std/Test.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
abstract contract NameManagerSpoke is IClusters {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    bool internal _inMulticall;

    address public immutable endpoint;

    uint256 internal immutable marketOpenTimestamp;

    uint256 internal constant BID_TIMELOCK = 30 days;

    IPricing internal pricing;

    /// @notice Which cluster an address belongs to
    mapping(bytes32 addr => uint256 clusterId) public addressToClusterId;

    /// @notice Which cluster a name belongs to
    mapping(bytes32 name => uint256 clusterId) public nameToClusterId;

    /// @notice Display name to be shown for a cluster, like ENS reverse records
    mapping(uint256 clusterId => bytes32 name) public defaultClusterName;

    /// @notice Enumerate all names owned by a cluster
    mapping(uint256 clusterId => EnumerableSetLib.Bytes32Set names) internal _clusterNames;

    /// @notice For example lookup[17]["hot"] -> 0x123...
    mapping(uint256 clusterId => mapping(bytes32 walletName => bytes32 addr)) public forwardLookup;

    /// @notice For example lookup[0x123...] -> "hot", then combine with cluster name in a diff method
    mapping(bytes32 addr => bytes32 walletName) public reverseLookup;

    /// @notice Data required for proper harberger tax calculation when pokeName() is called
    mapping(bytes32 name => IClusters.PriceIntegral integral) public priceIntegral;

    /// @notice The amount of money backing each name registration
    mapping(bytes32 name => uint256 amount) public nameBacking;

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(bytes32 name => IClusters.Bid bidData) public bids;

    /// @notice Failed bid refunds are pooled so we don't have to revert when the highest bid is outbid
    mapping(bytes32 bidder => uint256 refund) public bidRefunds;

    /**
     * PROTOCOL INVARIANT TRACKING
     * address(this).balance >= protocolAccrual + totalNameBacking + totalBidBacking
     */

    /// @notice Amount of eth that's transferred from nameBacking to the protocol
    uint256 public protocolAccrual;

    /// @notice Amount of eth that's backing names
    uint256 public totalNameBacking;

    /// @notice Amount of eth that's sitting in active bids and canceled but not-yet-withdrawn bids
    uint256 public totalBidBacking;

    /// @dev Ensures balance invariant holds
    function _checkInvariant() internal view {
        if (address(this).balance < protocolAccrual + totalNameBacking + totalBidBacking) revert BadInvariant();
    }

    /// @dev Ensure name is valid (not empty or too long)
    function _checkNameValid(string memory name) internal pure {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(name).length > 32) revert LongName();
    }

    /// @dev Ensure addr owns name
    function _checkNameOwnership(bytes32 addr, string memory name) internal view {
        if (addressToClusterId[addr] == 0) revert NoCluster();
        if (bytes(name).length == 0) return; // Short circuit for reset as cluster addresses never own name ""
        if (addressToClusterId[addr] != nameToClusterId[_stringToBytes32(name)]) revert Unauthorized();
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

    /// @dev Hook used to check if an address is either unverified or verified
    function _hookCheck(uint256 clusterId, bytes32 addr) internal virtual;

    /// @notice Used to restrict external functions to endpoint
    /// @dev This version ignores if msg.sender == msgSender as users wont be allowed to use these functions on spokes
    modifier onlyEndpoint() {
        if (msg.sender != endpoint) revert Unauthorized();
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

    /// ECONOMIC FUNCTIONS ///

    /// @notice Buy unregistered name. Must pay at least minimum yearly payment.
    /// @dev Processing is handled in overload
    function buyName(uint256 msgValue, string memory name) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("buyName(bytes32,uint256,string)", _addressToBytes32(msg.sender), msgValue, name);
        if (_inMulticall) return payload;
        else return IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
    }

    /// @notice buyName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _stringToBytes32(name);
        uint256 clusterId = addressToClusterId[msgSender];
        _fixZeroCluster(msgSender);
        // Process price accounting updates
        nameBacking[_name] += msgValue;
        totalNameBacking += msgValue;
        priceIntegral[_name] =
            IClusters.PriceIntegral({lastUpdatedTimestamp: block.timestamp, lastUpdatedPrice: pricing.minAnnualPrice()});
        _assignName(_name, clusterId);
        if (defaultClusterName[clusterId] == bytes32("")) {
            defaultClusterName[clusterId] = _name;
            emit DefaultClusterName(_name, clusterId);
        }
        emit BuyName(_name, clusterId, msgValue);

        _checkInvariant();
        return bytes("");
    }

    /// @notice Fund an existing and specific name, callable by anyone
    /// @dev Processing is handled in overload
    function fundName(uint256 msgValue, string memory name) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("fundName(bytes32,uint256,string)", _addressToBytes32(msg.sender), msgValue, name);
        if (_inMulticall) return payload;
        else return IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
    }

    /// @notice fundName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function fundName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _toBytes32(name);
        nameBacking[_name] += msgValue;
        totalNameBacking += msgValue;
        emit FundName(_name, msgSender, msgValue);

        _checkInvariant();
        return bytes("");
    }

    /// @notice Move name from one cluster to another without payment
    /// @dev Processing is handled in overload
    function transferName(string memory name, uint256 toClusterId) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("transferName(bytes32,string,uint256)", _addressToBytes32(msg.sender), name, toClusterId);
        if (_inMulticall) return payload;
        else return IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
    }

    /// @notice transferName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function transferName(bytes32 msgSender, string memory name, uint256 toClusterId)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        uint256 fromClusterId = addressToClusterId[msgSender];
        _transferName(_stringToBytes32(name), fromClusterId, toClusterId);
        // Purge all addresses from cluster if last name was transferred out
        if (_clusterNames[fromClusterId].length() == 0) _hookDelete(fromClusterId);
        return bytes("");
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
            // Purge canonical name if necessary
            if (defaultClusterName[fromClusterId] == name) delete defaultClusterName[fromClusterId];
        } else {
            // Purge name assignment and remove from cluster
            _unassignName(name, fromClusterId);
        }
        emit TransferName(name, fromClusterId, toClusterId);
    }

    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and transfer names upon expiry to highest
    ///         sufficient bidder. If no bids above yearly minimum, delete name registration.
    function pokeName(string memory name) public payable returns (bytes memory payload) {
        if (msg.sender != endpoint) {
            payload = abi.encodeWithSignature("pokeName(string)", name);
            if (_inMulticall) return payload;
            else return IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
        } else {
            bytes32 _name = _stringToBytes32(name);
            IClusters.PriceIntegral memory integral = priceIntegral[_name];
            (uint256 spent, uint256 newPrice) =
                pricing.getIntegratedPrice(integral.lastUpdatedPrice, block.timestamp - integral.lastUpdatedTimestamp);
            // If out of backing (expired), transfer to highest sufficient bidder or delete registration
            uint256 backing = nameBacking[_name];
            if (spent >= backing) {
                delete nameBacking[_name];
                totalNameBacking -= backing;
                protocolAccrual += backing;
                // If there is a valid bid, transfer to the bidder
                bytes32 bidder;
                uint256 bid = bids[_name].ethAmount;
                if (bid > 0) {
                    bidder = bids[_name].bidder;
                    _fixZeroCluster(bidder);
                    nameBacking[_name] += bid;
                    totalNameBacking += bid;
                    totalBidBacking -= bid;
                    delete bids[_name];
                }
                // If there isn't a highest bidder, name will expire and be deleted as bidder is bytes32(0)
                _transferName(_name, nameToClusterId[_name], addressToClusterId[bidder]);
            } else {
                // Process price data update
                nameBacking[_name] -= spent;
                totalNameBacking -= spent;
                protocolAccrual += spent;
                priceIntegral[_name] =
                    IClusters.PriceIntegral({lastUpdatedTimestamp: block.timestamp, lastUpdatedPrice: newPrice});
            }
            emit PokeName(_name);
            return bytes("");
        }
    }

    /// @notice Place bids on valid names. Subsequent calls increases existing bid. If name is expired update ownership.
    ///         All bids timelocked for 30 days, unless they are outbid in which they are returned. Increasing a bid
    ///         resets the timelock.
    /// @dev Should work smoothly for fully expired names and names partway through their duration
    /// @dev Needs to be onchain ETH bid escrowed in one place because otherwise prices shift
    /// @dev Processing is handled in overload
    function bidName(uint256 msgValue, string memory name) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("bidName(bytes32,uint256,string)", _addressToBytes32(msg.sender), msgValue, name);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
    }

    /// @notice bidName() overload used in endpoint, msgSender must be msg.sender or endpoint
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        _checkNameValid(name);
        _checkZeroCluster(msgSender);
        if (msgValue == 0) revert NoBid();
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = nameToClusterId[_name];
        if (clusterId == 0) revert Unregistered();
        // Prevent name owner from bidding on their own name
        if (clusterId == addressToClusterId[msgSender]) revert SelfBid();
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = bids[_name].ethAmount;
        address prevBidder = bids[_name].bidder;
        // Revert if bid isn't sufficient or greater than the highest bid, bypass for highest bidder
        if (prevBidder != msgSender && (msgValue <= prevBid || msgValue < pricing.minAnnualPrice())) {
            revert Insufficient();
        }
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        else if (prevBidder == msgSender) {
            bids[_name].ethAmount += msgValue;
            totalBidBacking += msgValue;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidIncreased(_name, msgSender, prevBid + msgValue);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            bids[_name] = IClusters.Bid(msgValue, block.timestamp, msgSender);
            totalBidBacking += msgValue;
            emit BidPlaced(_name, msgSender, msgValue);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(prevBidder).call{value: prevBid}("");
                if (!success) {
                    bidRefunds[prevBidder] += prevBid;
                } else {
                    totalBidBacking -= prevBid;
                    emit BidRefunded(_name, prevBidder, msgValue);
                }
            }
        }
        // Update name status and transfer to highest bidder if expired
        pokeName(name);

        _checkInvariant();
        return bytes("");
    }

    /// @notice Reduce bid and refund difference. Revoke if amount is the total bid or is the max uint256 value.
    /// @dev Processing is handled in overload
    function reduceBid(string memory name, uint256 amount) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("reduceBid(address,string,uint256)", msg.sender, name, amount);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// @notice reduceBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function reduceBid(address msgSender, string memory name, uint256 amount)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        _checkNameValid(name);
        bytes32 _name = _toBytes32(name);
        uint256 bid = bids[_name].ethAmount;
        if (bid == 0) revert NoBid();
        if (bids[_name].bidder != msgSender) revert Unauthorized();
        // Prevent reducing or revoking a bid before the bid timelock is up
        if (block.timestamp < bids[_name].createdTimestamp + BID_TIMELOCK) revert Timelock();
        // Overwrite amount with total bid in assumption caller is revoking bid
        if (amount > bid) amount = bid;

        // Poke name to update backing and ownership (if required) prior to bid adjustment
        pokeName(name);
        // Short circuit if pokeName() processed transfer to bidder due to name expiry
        if (bids[_name].ethAmount == 0) return bytes("");

        // Revert if reduction will push bid beneath minAnnualPrice
        uint256 diff = bid - amount;
        if (diff != 0 && diff < pricing.minAnnualPrice()) revert Insufficient();

        // If reducing bid to 0 or by maximum uint256 value, revoke altogether
        if (diff == 0) {
            delete bids[_name];
            totalBidBacking -= bid;
            emit BidRevoked(_name, msgSender, bid);
        }
        // Otherwise, decrease bid and update timestamp
        else {
            bids[_name].ethAmount -= amount;
            totalBidBacking -= amount;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidReduced(_name, msgSender, amount);
        }

        // Transfer bid reduction after all state is purged to prevent reentrancy
        // This bid refund reverts upon failure because it isn't happening in a forced context such as being outbid
        (bool success,) = payable(msgSender).call{value: amount}("");
        if (!success) revert NativeTokenTransferFailed();
        return bytes("");
    }

    /// @notice Accept bid and transfer name to bidder
    /// @dev Retrieves bid, adjusts state, then sends payment to avoid reentrancy
    /// @dev Processing is handled in overload
    function acceptBid(string memory name) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("acceptBid(address,string)", msg.sender, name);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// @notice acceptBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function acceptBid(address msgSender, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory payload)
    {
        _checkNameValid(name);
        _checkZeroCluster(msgSender);
        _checkNameOwnership(msgSender, name);
        bytes32 _name = _toBytes32(name);
        Bid memory bid = bids[_name];
        if (bid.ethAmount == 0) revert NoBid();
        delete bids[_name];
        totalBidBacking -= bid.ethAmount;
        _transferName(_name, nameToClusterId[_name], addressToClusterId[bid.bidder]);
        (bool success,) = payable(msgSender).call{value: bid.ethAmount}("");
        if (!success) revert NativeTokenTransferFailed();
        return bytes("");
    }

    /// @notice Allow failed bid refunds to be withdrawn
    /// @dev Processing is handled in overload
    function refundBid() public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("refundBid(address)", msg.sender);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// @notice acceptBid() overload used by endpoint, msgSender must be msg.sender or endpoint
    function refundBid(address msgSender) public payable onlyEndpoint returns (bytes memory) {
        uint256 refund = bidRefunds[msgSender];
        if (refund == 0) revert NoBid();
        delete bidRefunds[msgSender];
        totalBidBacking -= refund;
        (bool success,) = payable(msgSender).call{value: refund}("");
        if (!success) revert NativeTokenTransferFailed();
        return bytes("");
    }

    /// LOCAL NAME MANAGEMENT ///

    /// @notice Set canonical name or erase it by setting ""
    /// @dev Processing is handled in overload
    function setDefaultClusterName(string memory name) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("setDefaultClusterName(address,string)", msg.sender, name);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// @notice setDefaultClusterName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function setDefaultClusterName(address msgSender, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        if (bytes(name).length > 32) revert LongName();
        _checkZeroCluster(msgSender);
        _checkNameOwnership(msgSender, name);
        bytes32 _name = _toBytes32(name);
        uint256 clusterId = addressToClusterId[msgSender];
        if (bytes(name).length == 0) {
            delete defaultClusterName[clusterId];
            emit DefaultClusterName(bytes32(""), clusterId);
        } else {
            defaultClusterName[clusterId] = _name;
            emit DefaultClusterName(_name, clusterId);
        }
        return bytes("");
    }

    /// @notice Set wallet name for msg.sender or erase it by setting ""
    /// @dev Processing is handled in overload
    function setWalletName(address addr, string memory walletName) public payable returns (bytes memory payload) {
        payload = abi.encodeWithSignature("setWalletName(address,address,string)", msg.sender, addr, walletName);
        if (_inMulticall) return payload;
        else IEndpoint(endpoint).lzSend(msg.sender, payload, msg.value, bytes(""));
    }

    /// @notice setWalletName() overload used by endpoint, msgSender must be msg.sender or endpoint
    function setWalletName(address msgSender, address addr, string memory walletName)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        if (bytes(walletName).length > 32) revert LongName();
        _checkZeroCluster(msgSender);
        bytes32 _walletName = _toBytes32(walletName);
        uint256 clusterId = addressToClusterId[msgSender];
        if (clusterId != addressToClusterId[addr]) revert Unauthorized();
        if (bytes(walletName).length == 0) {
            _walletName = reverseLookup[addr];
            delete forwardLookup[clusterId][_walletName];
            delete reverseLookup[addr];
            emit SetWalletName(bytes32(""), addr);
        } else {
            forwardLookup[clusterId][_walletName] = addr;
            reverseLookup[addr] = _walletName;
            emit SetWalletName(_walletName, addr);
        }
        return bytes("");
    }

    /// @dev Set name-related state variables
    function _assignName(bytes32 name, uint256 clusterId) internal {
        nameToClusterId[name] = clusterId;
        _clusterNames[clusterId].add(name);
    }

    /// @dev Purge name-related state variables
    function _unassignName(bytes32 name, uint256 clusterId) internal {
        nameToClusterId[name] = 0;
        if (defaultClusterName[clusterId] == name) {
            delete defaultClusterName[clusterId];
            emit DefaultClusterName(bytes32(""), clusterId);
        }
        _clusterNames[clusterId].remove(name);
    }

    /// STRING HELPERS ///

    /// @dev Returns bytes32 representation of string < 32 characters, used in name-related state vars and functions
    function _stringToBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        return bytes32(smallBytes);
    }

    /// @dev Returns bytes32 representation of address
    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @dev Returns address representation of bytes32
    function _bytes32ToAddress(bytes32 addr) internal pure returns (address) {
        return address(uint160(uint256(addr)));
    }
}
