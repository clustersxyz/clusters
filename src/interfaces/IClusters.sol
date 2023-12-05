// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IClusters {
    /// STRUCTS ///

    struct PriceIntegral {
        uint256 lastUpdatedTimestamp;
        uint256 lastUpdatedPrice;
    }

    /// @notice All relevant information for an individual bid
    struct Bid {
        uint256 ethAmount;
        uint256 createdTimestamp;
        bytes32 bidder;
    }

    /// EVENTS ///

    event Add(uint256 indexed clusterId, bytes32 indexed addr);
    event Remove(uint256 indexed clusterId, bytes32 indexed addr);
    event Verify(uint256 indexed clusterId, bytes32 indexed addr);
    event Delete(uint256 indexed clusterId);

    event BuyName(bytes32 indexed name, uint256 indexed clusterId, uint256 indexed amount);
    event FundName(bytes32 indexed name, bytes32 indexed funder, uint256 indexed amount);
    event TransferName(bytes32 indexed name, uint256 indexed fromClusterId, uint256 indexed toClusterId);
    event PokeName(bytes32 indexed name);
    event DefaultClusterName(bytes32 indexed name, uint256 indexed clusterId);
    event SetWalletName(bytes32 indexed walletName, bytes32 indexed wallet);

    event BidPlaced(bytes32 indexed name, address indexed bidder, uint256 indexed amount);
    event BidRefunded(bytes32 indexed name, address indexed bidder, uint256 indexed amount);
    event BidIncreased(bytes32 indexed name, address indexed bidder, uint256 indexed amount);
    event BidReduced(bytes32 indexed name, address indexed bidder, uint256 indexed amount);
    event BidRevoked(bytes32 indexed name, address indexed bidder, uint256 indexed amount);

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
    error Unregistered();
    error Unauthorized();
    error Insufficient();
    error BadInvariant();
    error MulticallFailed();
    error NativeTokenTransferFailed();

    /// STORAGE / VIEW FUNCTIONS ///

    function endpoint() external view returns (address endpoint);
    function nextClusterId() external view returns (uint256 clusterId);
    function addressToClusterId(bytes32 addr) external view returns (uint256 clusterId);
    function nameToClusterId(bytes32 name) external view returns (uint256 clusterId);
    function defaultClusterName(uint256 clusterId) external view returns (bytes32 name);
    function forwardLookup(uint256 clusterId, bytes32 walletName) external view returns (bytes32 addr);
    function reverseLookup(bytes32 addr) external view returns (bytes32 walletName);

    function priceIntegral(bytes32 name)
        external
        view
        returns (uint256 lastUpdatedTimestamp, uint256 lastUpdatedPrice);
    function nameBacking(bytes32 name) external view returns (uint256 ethAmount);
    function bids(bytes32 name) external view returns (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder);
    function bidRefunds(bytes32 _bidder) external view returns (uint256 refund);

    function protocolAccrual() external view returns (uint256 accrual);
    function totalNameBacking() external view returns (uint256 nameBacking);
    function totalBidBacking() external view returns (uint256 bidBacking);

    function getUnverifiedAddresses(uint256 clusterId) external view returns (bytes32[] memory addresses);
    function getVerifiedAddresses(uint256 clusterId) external view returns (bytes32[] memory addresses);
    function getClusterNamesBytes32(uint256 clusterId) external view returns (bytes32[] memory names);

    /// EXTERNAL FUNCTIONS ///

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function create() external payable returns (bytes memory);
    function create(address msgSender) external payable;
    function add(address addr) external payable returns (bytes memory);
    function add(address msgSender, address addr) external payable;
    function remove(address addr) external payable returns (bytes memory);
    function remove(address msgSender, address addr) external payable;

    function buyName(uint256 msgValue, string memory name) external payable returns (bytes memory);
    function buyName(address msgSender, uint256 msgValue, string memory name) external payable;
    function fundName(uint256 msgValue, string memory name) external payable returns (bytes memory);
    function fundName(address msgSender, uint256 msgValue, string memory name) external payable;
    function transferName(string memory name, uint256 toClusterId) external payable returns (bytes memory);
    function transferName(address msgSender, string memory name, uint256 toClusterId) external payable;
    function pokeName(string memory name) external payable returns (bytes memory);

    function bidName(uint256 msgValue, string memory name) external payable returns (bytes memory);
    function bidName(address msgSender, uint256 msgValue, string memory name) external payable;
    function reduceBid(string memory name, uint256 amount) external payable returns (bytes memory);
    function reduceBid(address msgSender, string memory name, uint256 amount) external payable;
    function acceptBid(string memory name) external payable returns (bytes memory);
    function acceptBid(address msgSender, string memory name) external payable returns (uint256 bidAmount);
    function refundBid() external payable returns (bytes memory);
    function refundBid(address msgSender) external payable;

    function setDefaultClusterName(string memory name) external payable returns (bytes memory);
    function setDefaultClusterName(address msgSender, string memory name) external payable;
    function setWalletName(address addr, string memory walletName) external payable returns (bytes memory);
    function setWalletName(address msgSender, address addr, string memory walletName) external payable;
}

interface IEndpoint {
    function lzSend(
        uint16 dstChainId,
        address zroPaymentAddress,
        bytes memory payload,
        uint256 nativeFee,
        bytes memory adapterParams
    ) external;
}
