// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";

interface IClustersEndpoint {
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;
}

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable {
    address public clusters;
    address public signer;

    event SignerAddr(address indexed addr);
    event ClustersAddr(address indexed addr);

    constructor(address owner_, address signer_) {
        _initializeOwner(owner_);
        signer = signer_;
        emit SignerAddr(signer_);
    }

    /// @dev Returns bytes32 representation of address
    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function getEthSignedMessageHash(address to, string memory name) public pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(to, name)));
    }

    function verify(address to, string memory name, bytes calldata sig) public view returns (bool) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(to, name);
        return ECDSA.recoverCalldata(ethSignedMessageHash, sig) == signer;
    }

    function buyName(string memory name, bytes calldata sig) external payable {
        if (!verify(msg.sender, name, sig)) revert ECDSA.InvalidSignature();
        IClustersEndpoint(clusters).buyName{value: msg.value}(_addressToBytes(msg.sender), msg.value, name);
    }

    function setSigner(address signer_) external onlyOwner {
        signer = signer_;
        emit SignerAddr(signer_);
    }

    function setClustersAddr(address clusters_) external onlyOwner {
        clusters = clusters_;
        emit ClustersAddr(clusters_);
    }
}
