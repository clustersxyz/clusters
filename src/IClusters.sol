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

    event BuyName(string indexed name, uint256 indexed clusterId);
    event FundName(string indexed name, address indexed funder, uint256 indexed amount);
    event TransferName(bytes32 indexed name, uint256 indexed fromClusterId, uint256 indexed toClusterId);
    event PokeName(string indexed name, address indexed poker);
    event CanonicalName(string indexed name, uint256 indexed clusterId);
    event WalletName(string indexed walletname, address indexed wallet);

    event BidPlaced(string indexed name, address indexed bidder, uint256 indexed amount);
    event BidRefunded(string indexed name, address indexed bidder, uint256 indexed amount);
    event BidIncreased(string indexed name, address indexed bidder, uint256 indexed amount);
    event BidReduced(string indexed name, address indexed bidder, uint256 indexed amount);
    event BidRevoked(string indexed name, address indexed bidder, uint256 indexed amount);

    /// ERRORS ///

    error NoBid();
    error SelfBid();
    error Invalid();
    error Timelock();
    error LongName();
    error Insolvent();
    error EmptyName();
    error NoCluster();
    error Registered();
    error Unauthorized();
    error Unregistered();
    error Insufficient();
    error MulticallFailed();
    error NativeTokenTransferFailed();

    /// STORAGE / VIEW FUNCTIONS ///

    function endpoint() external view returns (address endpoint);
    function nextClusterId() external view returns (uint256 clusterId);
    function addressToClusterId(address addr) external view returns (uint256 clusterId);
    function nameToClusterId(bytes32 name) external view returns (uint256 clusterId);
    function canonicalClusterName(uint256 clusterId) external view returns (bytes32 name);
    function forwardLookup(uint256 clusterId, bytes32 walletname) external view returns (address addr);
    function reverseLookup(address addr) external view returns (bytes32 walletName);

    function priceIntegral(bytes32 name)
        external
        view
        returns (bytes32 name_, uint256 lastUpdatedTimestamp, uint256 lastUpdatedPrice);
    function nameBacking(bytes32 name) external view returns (uint256 ethAmount);
    function bids(bytes32 name) external view returns (uint256 ethAmount, uint256 createdTimestamp, address bidder);
    function bidRefunds(address _bidder) external view returns (uint256 refund);

    function protocolRevenue() external view returns (uint256 revenue);
    function totalNameBacking() external view returns (uint256 nameBacking);
    function totalBidBacking() external view returns (uint256 bidBacking);

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory addresses);
    function getClusterNamesBytes32(uint256 clusterId) external view returns (bytes32[] memory names);
    function getClusterNamesString(uint256 clusterId) external view returns (string[] memory names);
    function getBid(bytes32 name) external view returns (Bid memory bid);

    /// EXTERNAL FUNCTIONS ///

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
    // You must use these versions of the functions when using multicall()
    function buyName(string memory name, uint256 value) external payable;
    function fundName(string memory name, uint256 value) external payable;
    function bidName(string memory name, uint256 value) external payable;

    function create() external;
    function create(address msgSender) external;
    function add(address addr) external;
    function add(address msgSender, address addr) external;
    function remove(address addr) external;
    function remove(address msgSender, address addr) external;

    function buyName(string memory name) external payable;
    function fundName(string memory name) external payable;
    function transferName(string memory name, uint256 toClusterId) external;
    function pokeName(string memory name) external;

    function bidName(string memory name) external payable;
    function reduceBid(string memory name, uint256 amount) external;
    function acceptBid(string memory name) external returns (uint256 bidAmount);
    function refundBid() external;

    function setCanonicalName(string memory name) external;
    function setWalletName(address addr, string memory walletname) external;
}
