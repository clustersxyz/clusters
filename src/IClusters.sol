// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IClusters {
    /// ERRORS ///

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

    /// EVENTS ///

    event BuyName(string indexed _name, uint256 indexed clusterId);
    event FundName(string indexed _name, address indexed funder, uint256 indexed amount);
    event TransferName(bytes32 indexed name, uint256 indexed fromClusterId, uint256 indexed toClusterId);
    event PokeName(string indexed _name, address indexed poker);
    event CanonicalName(string indexed _name, uint256 indexed clusterId);
    event WalletName(string indexed _walletName, address indexed wallet);

    event BidPlaced(string indexed _name, address indexed bidder, uint256 indexed amount);
    event BidRefunded(string indexed _name, address indexed bidder, uint256 indexed amount);
    event BidIncreased(string indexed _name, address indexed bidder, uint256 indexed amount);
    event BidReduced(string indexed _name, address indexed bidder, uint256 indexed amount);
    event BidRevoked(string indexed _name, address indexed bidder, uint256 indexed amount);

    /// STRUCTS ///

    struct PriceIntegral {
        bytes32 name;
        uint256 lastUpdatedTimestamp;
        uint256 lastUpdatedPrice;
        uint256 maxExpiry;
    }

    /// @notice All relevant information for an individual bid
    struct Bid {
        uint256 ethAmount;
        uint256 createdTimestamp;
        address bidder;
    }

    /// STORAGE / VIEW FUNCTIONS ///

    function nextClusterId() external view returns (uint256 clusterId);
    function addressLookup(address _addr) external view returns (uint256 clusterId);
    function nameLookup(bytes32 _name) external view returns (uint256 clusterId);
    function canonicalClusterName(uint256 _clusterId) external view returns (bytes32 name);
    function forwardLookup(uint256 _clusterId, bytes32 _walletName) external view returns (address wallet);
    function reverseLookup(address _wallet) external view returns (bytes32 walletName);

    function priceIntegral(bytes32 _name)
        external
        view
        returns (bytes32 name, uint256 lastUpdatedTimestamp, uint256 lastUpdatedPrice, uint256 maxExpiry);
    function protocolRevenue() external view returns (uint256 revenue);
    function nameBacking(bytes32 _name) external view returns (uint256 ethAmount);
    function bids(bytes32 _name) external view returns (uint256 ethAmount, uint256 createdTimestamp, address bidder);
    function bidRefunds(address _bidder) external view returns (uint256 refund);

    function clusterAddresses(uint256 _clusterId) external view returns (address[] memory addresses);
    function getClusterNames(uint256 _clusterId) external view returns (bytes32[] memory names);
    function getBid(bytes32 _name) external view returns (Bid memory bid);

    /// EXTERNAL FUNCTIONS ///

    function create() external;
    function add(address _addr) external;
    function remove(address _addr) external;

    function buyName(string memory _name) external payable;
    function fundName(string memory _name) external payable;
    function transferName(string memory _name, uint256 _toClusterId) external;
    function pokeName(string memory _name) external;

    function bidName(string memory _name) external payable;
    function reduceBid(string memory _name, uint256 _amount) external;
    function acceptBid(string memory _name) external returns (uint256 bidAmount);
    function refundBid() external;

    function setCanonicalName(string memory _name) external;
    function setWalletName(address _addr, string memory _walletName) external;
}
