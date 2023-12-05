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
    error NestedMulticall();

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

    function _getFunctionSelector(string memory signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }

    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64, /*nonce*/ bytes calldata payload)
        external
        onlyLzEndpoint
    {
        // If srcAddress isn't a trusted remote, return to abort in nonblocking fashion
        if (!_checkLzSrcAddress(srcChainId, srcAddress)) return;
        bytes4 selector = bytes4(payload[:4]);
        bytes4 multicall = _getFunctionSelector("multicall(bytes[])");
        // If multicall, parse and verify inputs
        if (selector == multicall) {
            bytes[] memory data;
            address sender;
            (data, sender) = abi.decode(payload[4:], (bytes[], address));
            bytes4 pokeName = _getFunctionSelector("pokeName(string)");
            // Iterate through each call
            for (uint256 i; i < data.length; ++i) {
                bytes memory currentCall = data[i];
                assembly {
                    selector := mload(add(currentCall, 32))
                }
                if (selector == multicall) {
                    revert NestedMulticall();
                } // Prevent nested multicalls
                else {
                    // Validate msgSender param matches real sender
                    if (selector != pokeName) {
                        // pokeName() is the only exemption as it has no msgSender param
                        address msgSender;
                        assembly {
                            msgSender := mload(add(currentCall, 36))
                        }
                        if (msgSender != sender) revert InvalidSender();
                    }
                }
                // If validation doesn't fail, pass the calldata along
                (bool success,) = clusters.call(currentCall);
                if (!success) revert TxFailed();
            }
        } else {
            (bool success,) = clusters.call(payload);
            if (!success) revert TxFailed();
        }
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
