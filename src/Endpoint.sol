// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {ILayerZeroReceiver} from "../lib/LayerZero/contracts/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "../lib/LayerZero/contracts/interfaces/ILayerZeroEndpoint.sol";
import {IClusters} from "./IClusters.sol";

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable, ILayerZeroReceiver {
    error TxFailed();
    error InvalidArray();
    error InvalidSender();
    error NoTrustedRemote();

    event SoftAbort();

    address public clusters;
    address public immutable lzEndpoint;
    mapping(uint16 chainId => bytes remote) public lzTrustedRemotes;

    modifier onlyLzEndpoint() {
        if (msg.sender != lzEndpoint) revert Unauthorized();
        _;
    }

    modifier onlyClusters() {
        if (msg.sender != clusters) revert Unauthorized();
        _;
    }

    constructor(address lzEndpoint_) {
        lzEndpoint = lzEndpoint_;
        _initializeOwner(msg.sender);
    }

    function _checkLzSrcAddress(uint16 srcChainId, bytes memory srcAddress) internal view returns (bool) {
        if (keccak256(srcAddress) == keccak256(lzTrustedRemotes[srcChainId])) return true;
        else return false;
    }

    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64, /*nonce*/ bytes calldata payload)
        external
        onlyLzEndpoint
    {
        // If srcAddress isn't a trusted remote, return to abort in nonblocking fashion
        if (!_checkLzSrcAddress(srcChainId, srcAddress)) {
            emit SoftAbort();
            return;
        }
        (bool success,) = clusters.call(payload);
        if (!success) revert TxFailed();
    }

    function lzSend(
        uint16 dstChainId,
        address zroPaymentAddress,
        bytes memory payload,
        uint256 nativeFee,
        bytes memory adapterParams
    ) external payable onlyClusters {
        bytes memory trustedRemote = lzTrustedRemotes[dstChainId];
        if (trustedRemote.length == 0) revert NoTrustedRemote();
        ILayerZeroEndpoint(lzEndpoint).send{value: nativeFee}(
            dstChainId, trustedRemote, payload, payable(msg.sender), zroPaymentAddress, adapterParams
        );
    }

    function setClustersAddr(address clusters_) external onlyOwner {
        clusters = clusters_;
    }

    function setTrustedRemote(uint16 dstChainId, address addr, bool status) external onlyOwner {
        if (status) lzTrustedRemotes[dstChainId] = abi.encodePacked(addr, address(this));
        else delete lzTrustedRemotes[dstChainId];
    }

    function setTrustedRemotes(uint16[] memory dstChainId, address[] memory addr, bool[] memory status)
        external
        onlyOwner
    {
        if (dstChainId.length != addr.length || dstChainId.length != status.length) revert InvalidArray();
        for (uint256 i; i < dstChainId.length; ++i) {
            if (status[i]) lzTrustedRemotes[dstChainId[i]] = abi.encodePacked(addr[i], address(this));
            else delete lzTrustedRemotes[dstChainId[i]];
        }
    }
}
