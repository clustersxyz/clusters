// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IEndpoint {
    /// ERRORS ///

    error Invalid();
    error TxFailed();
    error RelayEid();
    error UnknownEid();
    error Unauthorized();
    error Insufficient();
    error MulticallFailed();

    /// EVENTS ///

    event Nonce(bytes32 indexed addr, uint256 indexed nonce);
    event SoftAbort();
    event SignerAddr(address indexed addr);
    event ClustersAddr(address indexed addr);

    /// STORAGE ///

    function clusters() external view returns (address);
    function signer() external view returns (address);
    function userNonces(bytes32 addr) external view returns (uint256);

    /// ECDSA HELPERS ///

    function getMulticallHash(bytes[] calldata data) external pure returns (bytes32);
    function getOrderHash(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        bytes32 bidder,
        string memory name
    ) external view returns (bytes32);
    function getEthSignedMessageHash(bytes32 messageHash) external pure returns (bytes32);

    function verifyMulticall(bytes[] calldata data, bytes calldata sig) external view returns (bool);
    function verifyOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        bytes32 bidder,
        string memory name,
        bytes calldata sig,
        address originator
    ) external view returns (bool);

    /// PERMISSIONED FUNCTIONS ///

    function multicall(bytes[] calldata data, bytes calldata sig) external payable returns (bytes[] memory results);
    function fulfillOrder(
        uint256 msgValue,
        uint256 nonce,
        uint256 expirationTimestamp,
        bytes32 authorized,
        string memory name,
        bytes calldata sig,
        address originator
    ) external payable;
    function invalidateOrder(uint256 nonce) external payable;

    /// ADMIN FUNCTIONS ///

    function setSignerAddr(address signer_) external;
    function setClustersAddr(address clusters_) external;

    /// LAYERZERO ///

    function setDstEid(uint32 eid) external;
    function quote(uint32 dstEid, bytes memory message, bytes memory options, bool payInLzToken) external returns (uint256 nativeFee, uint256 lzTokenFee);
    function sendPayload(bytes calldata payload) external payable returns (bytes memory result);
    function lzSend(bytes memory data, bytes memory options, uint256 nativeFee, address refundAddress)
        external
        payable
        returns (bytes memory);
    function lzSendMulticall(bytes[] memory data, bytes memory options, uint256 nativeFee, address refundAddress)
        external
        payable
        returns (bytes memory);
}
