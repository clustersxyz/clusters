// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "soledge/utils/ReentrancyGuard.sol";
import {ClustersCommunityBaseBeta} from "clusters/beta/ClustersCommunityBaseBeta.sol";
import {Origin, OAppReceiverUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppReceiverUpgradeable.sol";

contract ClustersCommunityHubBeta is OAppReceiverUpgradeable, ReentrancyGuard, ClustersCommunityBaseBeta {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     TRANSIENT STORAGE                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Transient storage slot to denote if the context is in the middle of a `_lzReceive`.
    uint256 internal constant _IN_LZ_RECEIVE_TRANSIENT_SLOT = 0;

    /// @dev Transient storage slot for the sender.
    uint256 internal constant _SENDER_TRANSIENT_SLOT = 1;

    /// @dev Transient storage slot for the message's origin chain ID.
    uint256 internal constant _CHAIN_ID_TRANSIENT_SLOT = 2;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when a bid is received.
    event Bid(
        bytes32 from, uint256 tokenChainId, address token, uint256 amount, bytes32 communityName, bytes32 walletName
    );

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Insufficient native payment.
    error InsufficientNativePayment();

    /// @dev The input arrays must have the same length.
    error ArrayLengthsMismatch();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the contract.
    function initialize(address endpoint_, address owner_) public initializer onlyProxy {
        _initializeOAppCore(endpoint_, owner_);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC WRITE FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Places a bid.
    ///      If any token is `address(0)`, it is treated as the native token.
    function placeBid(address token, uint256 amount, bytes32 communityName, bytes32 walletName)
        public
        payable
        nonReentrant
    {
        (bytes32 sender, uint256 chainId) = _senderAndChainId();
        if (chainId == block.chainid) {
            if (token == address(0)) {
                if (msg.value < amount) revert InsufficientNativePayment();
            } else {
                SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
            }
        }
        emit Bid(sender, chainId, token, amount, communityName, walletName);
    }

    /// @dev Places multiple bids.
    ///      If any token is `address(0)`, it is treated as the native token.
    function placeBids(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata communityNames,
        bytes32[] calldata walletNames
    ) public payable nonReentrant {
        (bytes32 sender, uint256 chainId) = _senderAndChainId();
        uint256 requiredNativeValue;
        if (tokens.length != amounts.length) revert ArrayLengthsMismatch();
        if (tokens.length != walletNames.length) revert ArrayLengthsMismatch();
        if (tokens.length != communityNames.length) revert ArrayLengthsMismatch();
        for (uint256 i; i < tokens.length; ++i) {
            address token = _get(tokens, i);
            uint256 amount = _get(amounts, i);
            if (chainId == block.chainid) {
                if (token == address(0)) {
                    requiredNativeValue += amount;
                } else {
                    SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
                }
            }
            emit Bid(sender, chainId, token, amount, _get(communityNames, i), _get(walletNames, i));
        }
        if (msg.value < requiredNativeValue) revert InsufficientNativePayment();
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         LAYERZERO                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For receiving a bid.
    function _lzReceive(
        Origin calldata, /* origin */
        bytes32, /* guid */
        bytes calldata message,
        address, /* executor */
        bytes calldata /* extraData */
    ) internal override {
        assembly ("memory-safe") {
            let chainId := calldataload(add(message.offset, 0x00))
            let sender := calldataload(add(message.offset, 0x20))

            let o := add(message.offset, calldataload(add(message.offset, 0x40)))
            let dataLength := calldataload(o)
            let dataOffset := add(o, 0x20)
            // Check that all of the data is within bounds.
            if or(lt(message.length, 0x60), gt(add(dataOffset, dataLength), add(message.offset, message.length))) {
                invalid()
            }

            tstore(_IN_LZ_RECEIVE_TRANSIENT_SLOT, address())
            tstore(_CHAIN_ID_TRANSIENT_SLOT, chainId)
            tstore(_SENDER_TRANSIENT_SLOT, sender)

            let m := mload(0x40)
            calldatacopy(m, dataOffset, dataLength)
            // Self-delegatecall with `data`.
            if iszero(delegatecall(gas(), address(), m, dataLength, 0x00, 0x00)) {
                // Bubble up the revert if the self-delegatecall fails.
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }

            tstore(_SENDER_TRANSIENT_SLOT, 0)
            tstore(_CHAIN_ID_TRANSIENT_SLOT, 0)
            tstore(_IN_LZ_RECEIVE_TRANSIENT_SLOT, 0)
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the sender and the chain ID,
    ///      using the values passed in via Layerzero if they are provided.
    function _senderAndChainId() internal view returns (bytes32 sender, uint256 chainId) {
        assembly ("memory-safe") {
            sender := caller()
            chainId := chainid()
            if tload(_IN_LZ_RECEIVE_TRANSIENT_SLOT) {
                sender := tload(_SENDER_TRANSIENT_SLOT)
                chainId := tload(_CHAIN_ID_TRANSIENT_SLOT)
            }
        }
    }
}
