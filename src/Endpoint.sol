// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    modifier onlyClusters() {
        if (msg.sender != clusters) revert Unauthorized();
        _;
    }

    constructor(address lzEndpoint_) {
        lzEndpoint = lzEndpoint_;
        _initializeOwner(msg.sender);
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

    function _relayMessage(uint64, /*nonce*/ bytes calldata payload) internal {
        uint256[] memory dstChainIds = _dstChainIds.values();
        for (uint256 i; i < dstChainIds.length; ++i) {
            ILayerZeroEndpoint(lzEndpoint).send{value: LAYERZERO_GAS_FEE}(
                uint16(dstChainIds[i]),
                lzTrustedRemotes[uint16(dstChainIds[i])],
                payload,
                payable(msg.sender),
                msg.sender,
                bytes("")
            );
        }
    }

    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        external
        onlyLzEndpoint
    {
        // If srcAddress isn't a trusted remote, return to abort in nonblocking fashion
        if (!_checkLzSrcAddress(srcChainId, srcAddress)) {
            emit SoftAbort();
            return;
        }
        // Only the relay chain will receive from Ethereum Mainnet, so if it does, relay to all other chains
        if (srcChainId == 101) _relayMessage(nonce, payload);
        (bool success,) = clusters.call(payload);
        if (!success) revert TxFailed();
    }

    function lzSend(address zroPaymentAddress, bytes memory payload, uint256 nativeFee, bytes memory adapterParams)
        external
        payable
        onlyClusters
    {
        // All endpoints only have one of two send paths: ETH -> Relay, Any -> ETH
        // Path is determined by checking if native chainId is 1, which indicates Ethereum Mainnet
        uint16 _dstChainId;
        if (block.chainid == 1) _dstChainId = dstChainId;
        else _dstChainId = 101;
        bytes memory trustedRemote = lzTrustedRemotes[_dstChainId];
        if (trustedRemote.length == 0) revert InvalidTrustedRemote();
        ILayerZeroEndpoint(lzEndpoint).send{value: nativeFee}(
            _dstChainId, trustedRemote, payload, payable(msg.sender), zroPaymentAddress, adapterParams
        );
    }

    function setClustersAddr(address clusters_) external onlyOwner {
        clusters = clusters_;
    }

    function setDstChainId(uint16 dstChainId_) external onlyOwner {
        if (!_dstChainIds.contains(dstChainId_)) revert InvalidTrustedRemote();
        dstChainId = dstChainId_;
    }

    function addTrustedRemote(uint16 dstChainId_, address addr) external onlyOwner {
        if (!_dstChainIds.contains(dstChainId_) && dstChainId_ != 101) _dstChainIds.add(dstChainId_);
        lzTrustedRemotes[dstChainId_] = abi.encodePacked(addr, address(this));
    }

    function removeTrustedRemote(uint16 dstChainId_) external onlyOwner {
        if (dstChainId_ == dstChainId) revert RelayChainId();
        if (!_dstChainIds.contains(dstChainId_) && dstChainId_ != 101) _dstChainIds.remove(dstChainId_);
        delete lzTrustedRemotes[dstChainId_];
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
