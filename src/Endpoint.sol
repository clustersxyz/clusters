// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "../lib/forge-std/src/Test.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";

interface IClustersEndpoint {
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;
}

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable, IEndpoint {
    address public clusters;
    address public signer;

    constructor(address owner_, address signer_) {
        _initializeOwner(owner_);
        signer = signer_;
        emit SignerAddr(signer_);
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev Returns bytes32 representation of address
    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// ECDSA HELPERS ///

    function getEthSignedMessageHash(address to, string memory name) public pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(to, name)));
    }

    function verify(address to, string memory name, bytes calldata sig) public view returns (bool) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(to, name);
        return ECDSA.recoverCalldata(ethSignedMessageHash, sig) == signer;
    }

    /// PERMISSIONED BUY FUNCTIONS ///

    function buyName(uint256 msgValue, string memory name, bytes calldata sig) external payable {
        if (!verify(msg.sender, name, sig)) revert ECDSA.InvalidSignature();
        IClustersEndpoint(clusters).buyName{value: msgValue}(_addressToBytes(msg.sender), msgValue, name);
    }

    /// ADMIN FUNCTIONS ///

    function setSigner(address signer_) external onlyOwner {
        signer = signer_;
        emit SignerAddr(signer_);
    }

    function setClustersAddr(address clusters_) external onlyOwner {
        clusters = clusters_;
        emit ClustersAddr(clusters_);
    }
}
