// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {ILayerZeroReceiver} from "../lib/LayerZero/contracts/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "../lib/LayerZero/contracts/interfaces/ILayerZeroEndpoint.sol";
import {IClusters} from "./IClusters.sol";
import {BytesLib} from "../lib/solidity-bytes-utils/contracts/BytesLib.sol";

// TODO: Make this a proxy contract to swap out logic, ownership can be reverted later

contract Endpoint is Ownable, ILayerZeroReceiver {
    using BytesLib for bytes;

    error InvalidArray();
    error InvalidTxType();
    error NoTrustedRemote();

    enum TxType {
        NONE,
        MULTICALL,
        CREATE,
        ADD,
        REMOVE,
        BUY,
        FUND,
        TRANSFER,
        POKE,
        BID,
        REDUCE,
        ACCEPT,
        DEFAULTNAME,
        WALLETNAME
    }

    /// @dev This must always be equal with TxType length or enshrined in production
    uint8 internal constant TXTYPE_COUNT = 14;

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
        if (srcAddress.equal(lzTrustedRemotes[srcChainId])) return true;
        else return false;
    }

    function _checkTxType(bytes memory data) internal pure returns (TxType) {
        uint8 txType = uint8(data[0]);
        if (txType == 0 || txType >= TXTYPE_COUNT) revert InvalidTxType();
        return TxType(txType);
    }

    function _routeCall(address msgSender, bytes memory data) internal {
        TxType txType = _checkTxType(data);
        if (txType == TxType.MULTICALL) {
            revert InvalidTxType();
        } // Prevent multicalls from being nested
        else if (txType == TxType.CREATE) {
            IClusters(clusters).create(msgSender);
        } else if (txType == TxType.ADD) {
            address addr;
            assembly {
                addr := mload(add(data, 1))
            }
            IClusters(clusters).add(msgSender, addr);
        } else if (txType == TxType.REMOVE) {
            address addr;
            assembly {
                addr := mload(add(data, 1))
            }
            IClusters(clusters).remove(msgSender, addr);
        } else if (txType == TxType.BUY) {
            return;
        } // TODO: Payable function msg.value handling
        else if (txType == TxType.FUND) {
            return;
        } // TODO: Payable function msg.value handling
        else if (txType == TxType.TRANSFER) {
            uint8 nameLength = uint8(data[1]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 34)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            uint256 offset = 2 + nameLength;
            uint256 toClusterId;
            assembly {
                toClusterId := mload(add(add(data, 32), offset))
            }
            IClusters(clusters).transferName(msgSender, name, toClusterId);
        } else if (txType == TxType.POKE) {
            uint8 nameLength = uint8(data[1]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 34)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            IClusters(clusters).pokeName(name);
        } else if (txType == TxType.BID) {
            return;
        } // TODO: Payable function msg.value handling
        else if (txType == TxType.REDUCE) {
            uint8 nameLength = uint8(data[1]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 34)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            uint256 offset = 2 + nameLength;
            uint256 amount;
            assembly {
                amount := mload(add(add(data, 32), offset))
            }
            IClusters(clusters).reduceBid(msgSender, name, amount);
        } else if (txType == TxType.ACCEPT) {
            uint8 nameLength = uint8(data[1]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 34)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            IClusters(clusters).acceptBid(msgSender, name);
        } else if (txType == TxType.DEFAULTNAME) {
            uint8 nameLength = uint8(data[1]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 34)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            IClusters(clusters).setDefaultClusterName(msgSender, name);
        } else if (txType == TxType.WALLETNAME) {
            uint160 addrRaw;
            address addr;
            assembly {
                addrRaw := mload(add(data, 21))
            }
            addr = address(addrRaw);

            uint8 nameLength = uint8(data[21]);
            string memory name;
            assembly {
                name := mload(0x40)
                mstore(name, nameLength)
                let src := add(data, 54)
                mstore(add(name, 32), mload(src))
                mstore(0x40, add(add(name, 64), nameLength))
            }
            IClusters(clusters).setWalletName(msgSender, addr, name);
        }
    }

    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64, /*nonce*/ bytes calldata payload)
        external
        onlyLzEndpoint
    {
        // If srcAddress isn't a trusted remote, return to abort in nonblocking fashion
        if (!_checkLzSrcAddress(srcChainId, srcAddress)) return;
        TxType txType = _checkTxType(payload);
        address sender = address(uint160(uint256(bytes32(payload[1:21]))));
        if (txType == TxType.MULTICALL) {
            bytes[] memory calls = abi.decode(payload[21:], (bytes[])); // TxType + Sender Address == 21 byte offset
            for (uint256 i; i < calls.length; ++i) {
                _routeCall(sender, calls[i]);
            }
        } else {
            _routeCall(sender, payload);
        }
    }

    function lzSend(
        uint16 dstChainId,
        address zroPaymentAddress,
        bytes memory payload,
        uint256 nativeFee,
        bytes memory adapterParams
    ) external onlyClusters {
        ILayerZeroEndpoint(lzEndpoint).send{value: nativeFee}(
            dstChainId, lzTrustedRemotes[dstChainId], payload, payable(msg.sender), zroPaymentAddress, adapterParams
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
