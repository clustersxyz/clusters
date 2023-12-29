// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OApp, Origin, MessagingFee} from "layerzero-oapp/contracts/oapp/OApp.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {EnumerableSetLib} from "./EnumerableSetLib.sol";
import {console2} from "forge-std/Test.sol";

interface IClustersHubEndpoint {
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

    bytes4 internal constant MULTICALL_SELECTOR = bytes4(keccak256("multicall(bytes[])"));
    bytes4 internal constant POKE_NAME_SELECTOR = bytes4(keccak256("pokeName(string)"));
    bytes4 internal constant REDUCE_BID_SELECTOR = bytes4(keccak256("reduceBid(bytes32,string,uint256)"));
    bytes4 internal constant ACCEPT_BID_SELECTOR = bytes4(keccak256("acceptBid(bytes32,string)"));

    uint32 public dstEid;
    address public clusters;
    address public signer;
    mapping(bytes32 addr => uint256 nonce) public userNonces;
    mapping(bytes32 addr => uint256 refund) public failedTxRefunds;

    EnumerableSetLib.Bytes32Set internal _dstEids;

    modifier onlyClusters() {
        if (msg.sender != clusters) revert Unauthorized();
        _;
    }

    constructor(address owner_, address signer_, address lzEndpoint) OApp(lzEndpoint, owner_) {
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

    /// @dev Returns bytes4 function selector
    function _getFuncSelector(bytes memory data) internal pure returns (bytes4 selector) {
        assembly {
            selector := mload(add(data, 32))
        }
    }

    /// @dev Returns bytes32 msgSender calldata parameter
    function _getMsgSender(bytes memory data) internal pure returns (bytes32 msgSender) {
        assembly {
            msgSender := mload(add(data, 36)) // skip 32 bytes for bytes array length and 4 for function selector
        }
    }

    /// @dev Returns true if msgSender in the provided calldata matches a particular address, true for pokeName()
    function _validateMsgSender(bytes32 msgSender, bytes memory data) internal pure returns (bool) {
        if (_getFuncSelector(data) == POKE_NAME_SELECTOR) return true;
        bytes32 _msgSender = _getMsgSender(data);
        if (msgSender == _msgSender) return true;
        else return false;
    }

    /// ECDSA HELPERS ///

    function getMulticallHash(bytes[] calldata data) public pure returns (bytes32) {
        return keccak256(abi.encode(data));
    }

    function getOrderHash(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        bytes32 bidder,
        string memory name
    ) public view returns (bytes32) {
        bytes32 callerBytes = _addressToBytes32(msg.sender);
        if (userNonces[callerBytes] > nonce) return bytes32("");
        if (block.timestamp > expirationTimestamp) return bytes32("");
        return keccak256(abi.encodePacked(nonce, expirationTimestamp, ethAmount, bidder, _stringToBytes32(name)));
    }

    function getEthSignedMessageHash(bytes32 messageHash) public pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(messageHash);
    }

    /// @dev Confirms if signature was for Ethereum signed message hash
    function _verify(bytes32 messageHash, bytes calldata sig, address signer_) internal view returns (bool) {
        return ECDSA.recoverCalldata(getEthSignedMessageHash(messageHash), sig) == signer_;
    }

    function verifyOrder(
        uint256 nonce,
        uint256 expirationTimestamp,
        uint256 ethAmount,
        bytes32 bidder,
        string memory name,
        bytes calldata sig,
        address originator
    ) public view returns (bool) {
        if (sig.length == 0) return false;
        if (userNonces[_addressToBytes32(originator)] > nonce) return false;
        if (block.timestamp > expirationTimestamp) return false;
        return _verify(getOrderHash(nonce, expirationTimestamp, ethAmount, bidder, name), sig, originator);
    }

    function verifyMulticall(bytes[] calldata data, bytes calldata sig) public view returns (bool) {
        return _verify(getMulticallHash(data), sig, signer);
    }

    /// PERMISSIONED FUNCTIONS ///

    function multicall(bytes[] calldata data, bytes calldata sig) external payable returns (bytes[] memory results) {
        if (!verifyMulticall(data, sig)) revert ECDSA.InvalidSignature();
        results = IClustersHubEndpoint(clusters).multicall{value: msg.value}(data);
    }

    function fulfillOrder(
        uint256 msgValue,
        uint256 nonce,
        uint256 expirationTimestamp,
        bytes32 authorized,
        string memory name,
        bytes calldata sig,
        address originator
    ) external payable {
        bool isValid = verifyOrder(nonce, expirationTimestamp, msgValue, authorized, name, sig, originator);
        (uint256 bidAmount,,) = IClustersHubEndpoint(clusters).bids(_stringToBytes32(name));

        if (msg.value < msgValue || msgValue <= bidAmount) revert Insufficient();
        if (!isValid) revert Invalid();
        IClustersHubEndpoint(clusters).bidName{value: msg.value}(_addressToBytes32(msg.sender), msg.value, name);
        {
            bytes32 originatorBytes = _addressToBytes32(originator);
            IClustersHubEndpoint(clusters).acceptBid{value: 0}(originatorBytes, name);
            userNonces[originatorBytes] = ++nonce;
            emit Nonce(originatorBytes, nonce);
        }
    }

    function invalidateOrder(uint256 nonce) external payable {
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
        emit ClustersAddr(clusters_);
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

    function quote(uint32 dstEid_, bytes memory message, bytes memory options, bool payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        MessagingFee memory msgQuote = _quote(dstEid_, message, options, payInLzToken);
        nativeFee = msgQuote.nativeFee;
        lzTokenFee = msgQuote.lzTokenFee;
    }

    function _validateQuote(uint32 dstEid_, bytes memory message, bytes memory options) internal {
        // TODO: Determine if we should force check fee param by retrieving onchain quote or just validate msg.value at
        // least covers the specified fee.
        (uint256 nativeFee,) = quote(dstEid_, message, options, false);
        if (msg.value < nativeFee) revert Insufficient();
    }

    function sendPayload(bytes calldata payload) external payable onlyClusters returns (bytes memory result) {
        // Short-circuit if dstEid isn't set for local-only functionality
        if (dstEid == 0) {
            IClustersHubEndpoint(clusters).noBridgeFundsReturn{value: msg.value}();
            return bytes("");
        }
        /*// TODO: Figure out how to assign these
        bytes memory options;
        MessagingFee memory fee;
        address refundAddress;
        _validateQuote(dstEid, payload, options);
        result = abi.encode(_lzSend(dstEid, payload, options, fee, refundAddress));*/
    }

    function lzSend(bytes memory data, bytes memory options, uint256 nativeFee, address refundAddress)
        external
        payable
        returns (bytes memory)
    {
        bytes4 selector = _getFuncSelector(data);
        if (selector == REDUCE_BID_SELECTOR || selector == ACCEPT_BID_SELECTOR) {
            revert Invalid();
        } else if (selector != POKE_NAME_SELECTOR) {
            if (!_validateMsgSender(_addressToBytes32(msg.sender), data)) revert Unauthorized();
        }

        // All endpoints only have one of two send paths: ETH -> Relay, Any -> ETH
        MessagingFee memory fee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
        return abi.encode(_lzSend(dstEid, data, options, fee, refundAddress));
    }

    function lzSendMulticall(bytes[] memory data, bytes memory options, uint256 nativeFee, address refundAddress)
        external
        payable
        returns (bytes memory)
    {
        for (uint256 i; i < data.length; ++i) {
            bytes4 selector = _getFuncSelector(data[i]);
            if (selector == REDUCE_BID_SELECTOR || selector == ACCEPT_BID_SELECTOR) {
                revert Invalid();
            } else if (selector != POKE_NAME_SELECTOR) {
                if (!_validateMsgSender(_addressToBytes32(msg.sender), data[i])) revert Unauthorized();
            }
        }
        bytes memory payload = abi.encodeWithSignature("multicall(bytes[])", data);
        MessagingFee memory fee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
        // All endpoints only have one of two send paths: ETH -> Relay, Any -> ETH
        return abi.encode(_lzSend(dstEid, payload, options, fee, refundAddress));
    }

    function _lzReceive(Origin calldata origin, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
    {
        (bool success,) = clusters.call{value: msg.value}(payload);
        if (!success) {
            bytes32 msgSender;
            bytes4 selector = _getFuncSelector(payload);

            if (selector == POKE_NAME_SELECTOR) {
                return;
            } else if (selector == MULTICALL_SELECTOR) {
                bytes[] memory data = abi.decode(payload[4:], (bytes[]));
                uint256 i;
                while (msgSender == bytes32("")) {
                    selector = _getFuncSelector(data[i]);
                    if (selector != POKE_NAME_SELECTOR) msgSender = _getMsgSender(data[i]);
                    ++i;
                }
            } else {
                msgSender = _getMsgSender(payload);
            }

            failedTxRefunds[msgSender] += msg.value;
            emit MessageFailed(origin.srcEid, origin.nonce, msgSender, msg.value);
        } else {
            /*// Only the relay chain will receive from Ethereum Mainnet, so if it does, relay to all other chains
            if (origin.srcEid == 30101) _relayMessage(payload);*/
        }
    }

    /*
    function _relayMessage(bytes calldata payload) internal {
        bytes32[] memory dstEids = _dstEids.values();
        for (uint256 i; i < dstEids.length; ++i) {
            // TODO: Figure out how to assign these
            bytes memory options;
            MessagingFee memory fee;
            address refundAddress;
            _lzSend(uint32(uint256(dstEids[i])), payload, options, fee, refundAddress);
        }
    }*/
}
