// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "../lib/forge-std/src/Test.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";

interface IClustersEndpoint {
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;

    function bids(bytes32 name) external view returns (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder);
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;
    function acceptBid(bytes32 msgSender, string memory name) external payable returns (uint256 bidAmount);
}

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable, IEndpoint {
    address public clusters;
    address public signer;
    mapping(bytes32 addr => uint256 nonce) public nonces;

    constructor(address owner_, address signer_) {
        _initializeOwner(owner_);
        signer = signer_;
        emit SignerAddr(signer_);
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Returns bytes32 representation of address
    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @dev Returns bytes32 representation of string
    function _stringToBytes32(string memory smallString) internal pure returns (bytes32) {
        bytes memory smallBytes = bytes(smallString);
        return bytes32(smallBytes);
    }

    /// ECDSA HELPERS ///

    function getEthSignedMessageHash(bytes32 to, string memory name) public pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(to, name)));
    }

    function verify(bytes32 to, string memory name, bytes calldata sig) public view returns (bool) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(to, name);
        return ECDSA.recoverCalldata(ethSignedMessageHash, sig) == signer;
    }

    function prepareOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        address bidder,
        string memory name
    ) public view returns (bytes32) {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (nonces[callerBytes] > nonce) return bytes32("");
        if (block.timestamp > expirationTimestamp) return bytes32("");
        return ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(nonce, expirationTimestamp, ethAmount, bidder, _stringToBytes32(name)))
        );
    }

    function verifyOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        address bidder,
        string memory name,
        bytes calldata sig,
        address originator
    ) public view returns (bool) {
        bytes32 originatorBytes = _addressToBytes32(originator);
        if (sig.length == 0) return false;
        if (nonces[originatorBytes] > nonce) return false;
        if (block.timestamp > expirationTimestamp) return false;
        bytes32 ethSignedMessageHash = prepareOrder(nonce, expirationTimestamp, ethAmount, bidder, name);
        return ECDSA.recoverCalldata(ethSignedMessageHash, sig) == originator;
    }

    /// PERMISSIONED FUNCTIONS ///

    function buyName(string memory name, bytes calldata sig) external payable {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (!verify(callerBytes, name, sig)) revert ECDSA.InvalidSignature();
        IClustersEndpoint(clusters).buyName{value: msg.value}(callerBytes, msg.value, name);
    }

    function fulfillOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        string memory name,
        bytes calldata sig,
        address originator
    ) external payable {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        bytes32 originatorBytes = _addressToBytes32(originator);
        bytes32 nameBytes = _stringToBytes32(name);
        bool isGeneralOrder = verifyOrder(nonce, expirationTimestamp, ethAmount, address(0), name, sig, originator);
        bool isSpecificOrder = verifyOrder(nonce, expirationTimestamp, ethAmount, msg.sender, name, sig, originator);
        (uint256 bidAmount,,) = IClustersEndpoint(clusters).bids(nameBytes);
        if (msg.value < ethAmount || msg.value <= bidAmount) revert Insufficient();
        if (!isGeneralOrder && !isSpecificOrder) revert Invalid();
        IClustersEndpoint(clusters).bidName{value: msg.value}(callerBytes, msg.value, name);
        IClustersEndpoint(clusters).acceptBid{value: 0}(originatorBytes, name);
    }

    function invalidateOrder(uint256 nonce) external {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (nonces[callerBytes] >= nonce) revert Invalid();
        nonces[callerBytes] = nonce;
        emit Nonce(callerBytes, nonce);
    }

    /// ADMIN FUNCTIONS ///

    function setSignerAddr(address signer_) external onlyOwner {
        signer = signer_;
        emit SignerAddr(signer_);
    }

    function setClustersAddr(address clusters_) external onlyOwner {
        clusters = clusters_;
        emit ClustersAddr(clusters_);
    }
}
