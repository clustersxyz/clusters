// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OApp} from "../lib/LayerZero-v2/oapp/contracts/oapp/OApp.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {ECDSA} from "../lib/solady/src/utils/ECDSA.sol";
import {EnumerableSetLib} from "./EnumerableSetLib.sol";
import {console2} from "../lib/forge-std/src/Test.sol";

interface IClustersEndpoint {
    function noBridgeFundsReturn() external payable;

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function buyName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;

    function bids(bytes32 name) external view returns (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder);
    function bidName(bytes32 msgSender, uint256 msgValue, string memory name) external payable;
    function acceptBid(bytes32 msgSender, string memory name) external payable returns (uint256 bidAmount);
}

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is OApp, IEndpoint {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    uint32 public dstEid;
    address public clusters;
    address public signer;
    mapping(bytes32 addr => uint256 nonce) public userNonces;

    EnumerableSetLib.Bytes32Set internal _dstEids;

    modifier onlyClusters() {
        if (msg.sender != clusters) revert Unauthorized();
        _;
    }

    constructor(address owner_, address signer_, address lzEndpoint) OApp(lzEndpoint, owner_) {
        signer = signer_;
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

    function prepareOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        address bidder,
        string memory name
    ) public view returns (bytes32) {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (userNonces[callerBytes] > nonce) return bytes32("");
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
        if (userNonces[originatorBytes] > nonce) return false;
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
        userNonces[originatorBytes] = ++nonce;
        emit Nonce(originatorBytes, nonce);
    }

    function invalidateOrder(uint256 nonce) external {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (userNonces[callerBytes] >= nonce) revert Invalid();
        userNonces[callerBytes] = nonce;
        emit Nonce(callerBytes, nonce);
    }

    /// ADMIN FUNCTIONS ///

    function setSignerAddr(address signer_) external onlyOwner {
        signer = signer_;
        emit SignerAddr(signer_);
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

    function setDstEid(uint32 eid) external onlyOwner {
        if (!_dstEids.contains(bytes32(uint256(eid)))) revert UnknownEid();
        dstEid = eid;
    }

    function setPeer(uint32 eid, bytes32 peer) public override onlyOwner {
        if (peer == bytes32(0)) {
            if (eid == dstEid) revert RelayEid();
            if (_dstEids.contains(bytes32(uint256(eid)))) {
                _dstEids.remove(bytes32(uint256(eid)));
            }
        } else {
            if (!_dstEids.contains(bytes32(uint256(eid)))) {
                _dstEids.add(bytes32(uint256(eid)));
            }
        }
        super.setPeer(eid, peer);
    }

    function sendPayload(bytes calldata payload) external payable onlyClusters {
        // TODO: Figure out how to assign these
        bytes memory options;
        MessagingFee memory fee;
        address refundAddress;
        result = _lzSend(payload, options, fee, refundAddress);
        if (result.length == 0) {
            IClustersEndpoint(clusters).noBridgeFundsReturn{value: msg.value}();
        }
    }

    function _lzSend(bytes memory message, bytes memory options, MessagingFee memory fee, address refundAddress)
        internal
        returns (MessagingReceipt memory receipt)
    {
        // Short-circuit if dstEid isn't set for local-only functionality
        if (dstEid == 0) return bytes("");
        // All endpoints only have one of two send paths: ETH -> Relay, Any -> ETH
        return abi.encode(_lzSend(dstEid, message, options, fee, refundAddress));
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata payload,
        address executor,
        bytes calldata extraData
    ) internal {
        // Only the relay chain will receive from Ethereum Mainnet, so if it does, relay to all other chains
        if (origin.srcEid == 30101) _relayMessage(payload);
        (bool success,) = clusters.call{value: msg.value}(payload);
        if (!success) revert TxFailed();
    }

    function _relayMessage(bytes calldata payload) internal {
        bytes32[] memory dstEids = _dstEids.values();
        for (uint256 i; i < dstEids.length; ++i) {
            // TODO: Figure out how to assign these
            bytes memory options;
            MessagingFee memory fee;
            address refundAddress;
            _lzSend(uint32(uint256(dstEids[i])), payload, options, fee, refundAddress);
        }
    }
}
