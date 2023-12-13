// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "../lib/forge-std/src/Test.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {ILayerZeroReceiver} from "../lib/LayerZero/contracts/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "../lib/LayerZero/contracts/interfaces/ILayerZeroEndpoint.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";
import {EnumerableSetLib} from "./EnumerableSetLib.sol";

interface IClustersEndpoint {
    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;

    function bids(bytes32 name) external view returns (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder);
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;
    function acceptBid(bytes32 msgSender, string memory name) external payable returns (uint256 bidAmount);
}

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable, IEndpoint, ILayerZeroReceiver {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    uint256 internal constant LAYERZERO_GAS_FEE = 200000 gwei;

    uint32 public dstEid;
    address public immutable lzEndpoint;
    address public clusters;
    address public signer;
    mapping(bytes32 addr => uint256 nonce) public nonces;
    mapping(uint32 dstEid => bytes32 peer) public lzTrustedPeers;

    EnumerableSetLib.Bytes32Set internal _dstEids;

    modifier onlyLzEndpoint() {
        if (msg.sender != lzEndpoint) revert Unauthorized();
        _;
    }

    modifier onlyClusters() {
        if (msg.sender != clusters) revert Unauthorized();
        _;
    }

    constructor(address owner_, address signer_, address lzEndpoint_) {
        _initializeOwner(owner_);
        signer = signer_;
        lzEndpoint = lzEndpoint_;
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

    function _checkLzSrcAddress(uint32 dstEid_, bytes32 memory sender) internal view returns (bool) {
        if (sender == lzTrustedPeers[dstEid_]) return true;
        else return false;
    }

    function _relayMessage(bytes calldata payload) internal {
        bytes32[] memory dstEids = _dstEids.values();
        bytes memory options;
        for (uint256 i; i < dstEids.length; ++i) {
            ILayerZeroEndpoint(lzEndpoint).send{value: LAYERZERO_GAS_FEE}(
                uint32(uint256(dstEids[i])),
                lzTrustedPeers[uint32(uint256(dstEids[i]))],
                payload,
                payable(msg.sender),
                msg.sender,
                bytes("")
            );
        }
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
        nonces[originatorBytes] = ++nonce;
        emit Nonce(originatorBytes, nonce);
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

    /// LAYERZERO FUNCTIONS ///

    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata payload,
        address executor,
        bytes calldata extraData
    ) internal {
        // If srcAddress isn't a trusted remote, return to abort in nonblocking fashion
        if (!_checkLzSrcAddress(origin.srcEid, origin.sender)) {
            emit SoftAbort();
            return;
        }
        // Only the relay chain will receive from Ethereum Mainnet, so if it does, relay to all other chains
        if (origin.srcEid == 101) _relayMessage(payload);
        (bool success,) = clusters.call(payload);
        if (!success) revert TxFailed();
    }

    function lzSend(bytes memory payload, bytes calldata options) external payable onlyClusters {
        // All endpoints only have one of two send paths: ETH -> Relay, Any -> ETH
        // Path is determined by checking if native chainId is 1, which indicates Ethereum Mainnet
        uint32 _dstEid;
        if (block.chainid == 1) _dstEid = dstEid;
        else _dstEid = 101;
        bytes32 memory peer = lzTrustedPeers[_dstEid];
        if (peer == bytes32("")) return;
        _lzSend(dstEid, payload, options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function setdstEid(uint32 dstEid_) external onlyOwner {
        if (!_dstEids.contains(bytes32(uint256(dstEid_)))) revert InvalidTrustedRemote();
        dstEid = dstEid_;
    }

    function addTrustedPeer(uint32 dstEid_, bytes32 peer) external onlyOwner {
        if (!_dstEids.contains(bytes32(uint256(dstEid_))) && dstEid_ != 101) {
            _dstEids.add(bytes32(uint256(dstEid_)));
        }
        lzTrustedPeers[dstEid_] = peer;
    }

    function removeTrustedRemote(uint32 dstEid_) external onlyOwner {
        if (dstEid_ == dstEid) revert RelayChainId();
        if (!_dstEids.contains(bytes32(uint256(dstEid_))) && dstEid_ != 101) {
            _dstEids.remove(bytes32(uint256(dstEid_)));
        }
        delete lzTrustedPeers[dstEid_];
    }
}
