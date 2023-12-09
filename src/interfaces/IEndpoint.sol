// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IEndpoint {
    event SignerAddr(address indexed addr);
    event ClustersAddr(address indexed addr);

    /// STORAGE ///

    function clusters() external view returns (address);
    function signer() external view returns (address);

    /// ECDSA HELPERS ///

    function getEthSignedMessageHash(address to, string memory name) external pure returns (bytes32);
    function verify(address to, string memory name, bytes calldata sig) external view returns (bool);

    /// PERMISSIONED BUY ///

    function buyName(uint256 msgValue, string memory name, bytes calldata sig) external payable;

    /// ADMIN FUNCTIONS ///

    function setSigner(address signer_) external;
    function setClustersAddr(address clusters_) external;
}
