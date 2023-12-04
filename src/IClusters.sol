// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IClusters {
    /// STRUCTS ///

    struct PriceIntegral {
        bytes32 name;
        uint256 lastUpdatedTimestamp;
        uint256 lastUpdatedPrice;
    }

    /// @notice All relevant information for an individual bid
    struct Bid {
        uint256 ethAmount;
        uint256 createdTimestamp;
        address bidder;
    }

    /// EVENTS ///

    event BuyName(string indexed name_, uint256 indexed clusterId);
    event FundName(string indexed name_, address indexed funder, uint256 indexed amount);
    event TransferName(bytes32 indexed name, uint256 indexed fromClusterId, uint256 indexed toClusterId);
    event PokeName(string indexed name_, address indexed poker);
    event CanonicalName(string indexed name_, uint256 indexed clusterId);
    event WalletName(string indexed walletName_, address indexed wallet);

    event BidPlaced(string indexed name_, address indexed bidder, uint256 indexed amount);
    event BidRefunded(string indexed name_, address indexed bidder, uint256 indexed amount);
    event BidIncreased(string indexed name_, address indexed bidder, uint256 indexed amount);
    event BidReduced(string indexed name_, address indexed bidder, uint256 indexed amount);
    event BidRevoked(string indexed name_, address indexed bidder, uint256 indexed amount);

    /// ERRORS ///

    error BadInvariant();
    error EmptyName();
    error NoBid();
    error SelfBid();
    error Invalid();
    error Timelock();
    error NoCluster();
    error Registered();
    error Unauthorized();
    error Unregistered();
    error Insufficient();
    error MulticallFailed();
    error NativeTokenTransferFailed();

    /// STORAGE / VIEW FUNCTIONS ///

    function nextClusterId() external view returns (uint256 clusterId);
    function addressToClusterId(address addr) external view returns (uint256 clusterId);
    function nameToClusterId(bytes32 name_) external view returns (uint256 clusterId);
    function canonicalClusterName(uint256 clusterId) external view returns (bytes32 name);
    function forwardLookup(uint256 clusterId, bytes32 walletName_) external view returns (address wallet);
    function reverseLookup(address _wallet) external view returns (bytes32 walletName);

    function priceIntegral(bytes32 name_)
        external
        view
        returns (bytes32 name, uint256 lastUpdatedTimestamp, uint256 lastUpdatedPrice);
    function protocolRevenue() external view returns (uint256 revenue);
    function nameBacking(bytes32 name_) external view returns (uint256 ethAmount);
    function bids(bytes32 name_) external view returns (uint256 ethAmount, uint256 createdTimestamp, address bidder);
    function bidRefunds(address _bidder) external view returns (uint256 refund);

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory addresses);
    function getClusterNames(uint256 clusterId) external view returns (bytes32[] memory names);
    function getBid(bytes32 name_) external view returns (Bid memory bid);

    /// EXTERNAL FUNCTIONS ///

    function create() external;
    function add(address addr) external;
    function remove(address addr) external;

    function buyName(string memory name_) external payable;
    function fundName(string memory name_) external payable;
    function transferName(string memory name_, uint256 toClusterId) external;
    function pokeName(string memory name_) external;

    function bidName(string memory name_) external payable;
    function reduceBid(string memory name_, uint256 amount) external;
    function acceptBid(string memory name_) external returns (uint256 bidAmount);
    function refundBid() external;

    function setCanonicalName(string memory name_) external;
    function setWalletName(address addr, string memory walletName_) external;
}
