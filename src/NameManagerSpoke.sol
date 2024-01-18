// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSetLib} from "./EnumerableSetLib.sol";

import {Ownable} from "solady/auth/Ownable.sol";

import {IPricing} from "./interfaces/IPricing.sol";

import {IClustersSpoke} from "./interfaces/IClustersSpoke.sol";

import {IEndpoint} from "./interfaces/IEndpoint.sol";

import {console2} from "forge-std/Test.sol";

/// @notice The bidding, accepting, eth storing component of Clusters. Handles name assignment
///         to cluster ids and checks auth of cluster membership before acting on one of its names
abstract contract NameManagerSpoke is IClustersSpoke, Ownable {
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
    mapping(bytes32 name => IClustersSpoke.PriceIntegral integral) public priceIntegral;

    /// @notice The amount of money backing each name registration
    mapping(bytes32 name => uint256 amount) public nameBacking;

    /// @notice Bid info storage, all bidIds are incremental and are not sorted by name
    mapping(bytes32 name => IClustersSpoke.Bid bidData) public bids;

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

    constructor(address owner_, address pricing_, address endpoint_, uint256 marketOpenTimestamp_) {
        if (marketOpenTimestamp_ < block.timestamp) revert Invalid();
        _initializeOwner(owner_);
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
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        _fixZeroCluster(msgSender);
        bytes32 _name = _stringToBytes32(name);
        uint256 clusterId = addressToClusterId[msgSender];
        // Process price accounting updates
        nameBacking[_name] += msgValue;
        totalNameBacking += msgValue;
        priceIntegral[_name] = IClustersSpoke.PriceIntegral({
            lastUpdatedTimestamp: block.timestamp,
            lastUpdatedPrice: pricing.minAnnualPrice()
        });
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
    function fundName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _stringToBytes32(name);
        nameBacking[_name] += msgValue;
        totalNameBacking += msgValue;
        emit FundName(_name, msgSender, msgValue);

        _checkInvariant();
        return bytes("");
    }

    /// @notice Move name from one cluster to another without payment
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
        // Assign name to new cluster, otherwise unassign
        if (toClusterId != 0) {
            _unassignName(name, fromClusterId);
            _assignName(name, toClusterId);
        } else {
            _unassignName(name, fromClusterId);
            // Convert remaining name backing to protocol accrual and soft refund any existing bid
            uint256 backing = nameBacking[name];
            delete nameBacking[name];
            totalNameBacking -= backing;
            protocolAccrual += backing;
            uint256 bid = bids[name].ethAmount;
            if (bid > 0) {
                bidRefunds[bids[name].bidder] += bid;
                delete bids[name];
            }
        }
        emit TransferName(name, fromClusterId, toClusterId);
    }

    // TODO: Figure out how pokeName() will be handled on spokes. Latency between mainnet and spoke calculations
    // needs to be addressed. Maybe just pass the values directly from mainnet instead of calculating them?
    /// @notice Move accrued revenue from ethBacked to protocolRevenue, and transfer names upon expiry to highest
    ///         sufficient bidder. If no bids above yearly minimum, delete name registration.
    function pokeName(string memory name) public payable returns (bytes memory payload) {
        if (msg.sender != endpoint) {
            payload = abi.encodeWithSignature("pokeName(string)", name);
            if (_inMulticall) return payload;
            else return IEndpoint(endpoint).sendPayload{value: msg.value}(payload);
        } else {
            bytes32 _name = _stringToBytes32(name);
            IClustersSpoke.PriceIntegral memory integral = priceIntegral[_name];
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
                    IClustersSpoke.PriceIntegral({lastUpdatedTimestamp: block.timestamp, lastUpdatedPrice: newPrice});
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
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _stringToBytes32(name);
        // Retrieve bidder values to process refund in case they're outbid
        uint256 prevBid = bids[_name].ethAmount;
        bytes32 prevBidder = bids[_name].bidder;
        // If the caller is the highest bidder, increase their bid and reset the timestamp
        if (prevBidder == msgSender) {
            bids[_name].ethAmount += msgValue;
            totalBidBacking += msgValue;
            // TODO: Determine which way is best to handle bid update timestamps
            // bids[_name].createdTimestamp = block.timestamp;
            emit BidIncreased(_name, msgSender, prevBid + msgValue);
        }
        // Process new highest bid
        else {
            // Overwrite previous bid
            bids[_name] = IClustersSpoke.Bid(msgValue, block.timestamp, msgSender);
            totalBidBacking += msgValue;
            emit BidPlaced(_name, msgSender, msgValue);
            // Process bid refund if there is one. Store balance for recipient if transfer fails instead of reverting.
            if (prevBid > 0) {
                (bool success,) = payable(_bytes32ToAddress(prevBidder)).call{value: prevBid}("");
                if (!success) {
                    bidRefunds[prevBidder] += prevBid;
                } else {
                    totalBidBacking -= prevBid;
                    emit BidRefunded(_name, prevBidder, msgValue);
                }
            }
        }
        // Update name status and transfer to highest bidder if expired
        // TODO: Revisit this call when spoke pokeName() logic is reevaluated
        pokeName(name);

        _checkInvariant();
        return bytes("");
    }

    /// @notice Reduce bid and refund difference. Revoke if amount is the total bid or is the max uint256 value.
    function reduceBid(bytes32 msgSender, string memory name, uint256 amount)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _stringToBytes32(name);
        uint256 bid = bids[_name].ethAmount;
        // Overwrite amount with total bid in assumption caller is revoking bid
        if (amount > bid) amount = bid;

        // Poke name to update backing and ownership (if required) prior to bid adjustment
        // TODO: Revisit this call when spoke pokeName() logic is reevaluated
        pokeName(name);

        // Skip bid reduction logic if pokeName() processed transfer to bidder due to name expiry
        if (bids[_name].ethAmount != 0) {
            uint256 diff = bid - amount;
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
        }
        return bytes("");
    }

    /// @notice Accept bid and transfer name to bidder
    /// @dev Retrieves bid, adjusts state, then sends payment to avoid reentrancy
    function acceptBid(bytes32 msgSender, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory payload)
    {
        bytes32 _name = _stringToBytes32(name);
        Bid memory bid = bids[_name];
        delete bids[_name];
        totalBidBacking -= bid.ethAmount;
        _fixZeroCluster(bid.bidder);
        _transferName(_name, addressToClusterId[msgSender], addressToClusterId[bid.bidder]);
        return bytes("");
    }

    /// @notice Allow failed bid refunds to be withdrawn
    function refundBid(bytes32 msgSender) public payable onlyEndpoint returns (bytes memory) {
        uint256 refund = bidRefunds[msgSender];
        delete bidRefunds[msgSender];
        totalBidBacking -= refund;
        return bytes("");
    }

    /// LOCAL NAME MANAGEMENT ///

    /// @notice Set canonical name
    function setDefaultClusterName(bytes32 msgSender, string memory name)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        bytes32 _name = _stringToBytes32(name);
        uint256 clusterId = addressToClusterId[msgSender];
        defaultClusterName[clusterId] = _name;
        emit DefaultClusterName(_name, clusterId);
        return bytes("");
    }

    /// @notice Set wallet name for addr
    function setWalletName(bytes32 msgSender, bytes32 addr, string memory walletName)
        public
        payable
        onlyEndpoint
        returns (bytes memory)
    {
        uint256 clusterId = addressToClusterId[msgSender];
        bytes32 _walletName = _stringToBytes32(walletName);
        if (bytes(walletName).length == 0) {
            _walletName = reverseLookup[addr];
            delete forwardLookup[clusterId][_walletName];
            delete reverseLookup[addr];
            emit SetWalletName(bytes32(""), addr);
        } else {
            bytes32 prev = reverseLookup[addr];
            if (prev != bytes32("")) delete forwardLookup[clusterId][prev];
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
        delete nameToClusterId[name];
        _clusterNames[clusterId].remove(name);
        // If name is default cluster name for clusterId, reassign to the name at index 0 in _clusterNames
        if (defaultClusterName[clusterId] == name) {
            if (_clusterNames[clusterId].length() == 0) {
                delete defaultClusterName[clusterId];
                emit DefaultClusterName(bytes32(""), clusterId);
            } else {
                bytes32 newDefaultName = _clusterNames[clusterId].at(0);
                defaultClusterName[clusterId] = newDefaultName;
                emit DefaultClusterName(newDefaultName, clusterId);
            }
        }
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
