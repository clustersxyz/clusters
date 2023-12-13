// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IEndpoint {
    error Invalid();
    error Insufficient();

    event Nonce(bytes32 indexed addr, uint256 indexed nonce);
    event SignerAddr(address indexed addr);
    event ClustersAddr(address indexed addr);

    /// STORAGE ///

    function clusters() external view returns (address);
    function signer() external view returns (address);
    function nonces(bytes32 addr) external view returns (uint256);

    /// ECDSA HELPERS ///

    function getEthSignedMessageHash(bytes32 to, string memory name) external pure returns (bytes32);
    function verify(bytes32 to, string memory name, bytes calldata sig) external view returns (bool);
    function prepareOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        address bidder,
        string memory name
    ) external view returns (bytes32);
    function verifyOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        address bidder,
        string memory name,
        bytes calldata sig,
        address originator
    ) external view returns (bool);

    /// PERMISSIONED FUNCTIONS ///

    function buyName(string memory name, bytes calldata sig) external payable;
    function fulfillOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        string memory name,
        bytes calldata sig,
        address originator
    ) external payable;
    function invalidateOrder(uint256 nonce) external;

    /// ADMIN FUNCTIONS ///

    function setSignerAddr(address signer_) external;
    function setClustersAddr(address clusters_) external;

    /// LAYERZERO ///

    function lzSend(address zroPaymentAddress, bytes memory payload, uint256 nativeFee, bytes memory adapterParams)
        external;
}
