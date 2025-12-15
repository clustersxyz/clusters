// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibBytes} from "solady/utils/LibBytes.sol";
import {ERC7821} from "solady/accounts/ERC7821.sol";
import {Origin, OAppReceiverUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppReceiverUpgradeable.sol";

/// @title MessageHubPodV1
/// @notice A hyper minimal smart account that is controlled by the MessageHubV1
///         This is used when the message comes from a non-Ethereum chain.
contract MessageHubPodV1 is ERC7821 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For ERC7821.
    function _execute(bytes32, bytes calldata, Call[] calldata calls, bytes calldata) internal virtual override {
        bytes memory args = LibClone.argsOnClone(address(this), 0x00, 0x34);
        assembly ("memory-safe") {
            let requiredCaller := shr(96, mload(add(args, 0x40))) // `mothership`.
            let requiredHash := mload(add(args, 0x20))
            let m := mload(0x40) // Cache the free memory pointer.
            if iszero(
                and( // All arguments are evaluated from last to first.
                    and(
                        // `keccak256(abi.encode(originalSender, originalSenderType)) == requiredHash`.
                        eq(keccak256(0x20, 0x40), requiredHash),
                        and(
                            eq(returndatasize(), 0x60), // `mothership` returns `0x60` bytes.
                            eq(caller(), requiredCaller) // The caller is the `mothership`.
                        )
                    ),
                    staticcall(gas(), requiredCaller, 0x00, 0x00, 0x00, 0x60)
                )
            ) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
            mstore(0x40, m) // Restore the free memory pointer.
        }
        _execute(calls, bytes32(0));
    }
}

/// @title MessageHubV1
/// @notice Generalized message hub for LayerZero.
contract MessageHubV1 is UUPSUpgradeable, OAppReceiverUpgradeable {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     TRANSIENT STORAGE                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The sender transient storage slot.
    uint256 internal constant _SENDER_TRANSIENT_SLOT = 0;

    /// @dev The original sender transient storage slot.
    uint256 internal constant _ORIGINAL_SENDER_TRANSIENT_SLOT = 1;

    /// @dev The original sender type transient storage slot.
    uint160 internal constant _ORIGINAL_SENDER_TYPE_TRANSIENT_SLOT = 2;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Reentrancy not supported.
    error Reentrancy();

    /// @dev Unauthorized access.
    error Unauthorized();

    /// @dev Original sender is zero.
    error OriginalSenderIsZero();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         IMMUTABLES                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The address of the pod implementation.
    address internal immutable _podImplementation = address(new MessageHubPodV1());

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the contract.
    function initialize(address endpoint_, address owner_) public initializer onlyProxy {
        _initializeOAppCore(endpoint_, owner_);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                            META                            */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name and version of the contract.
    function contractNameAndVersion() public pure returns (string memory, string memory) {
        return ("MessageHub", "1.0.0");
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the deterministic address of the sub account.
    function predictSubAccount(bytes32 originalSender, uint256 originalSenderType) public view returns (address) {
        bytes memory args = _subAccountArgs(originalSender, originalSenderType);
        return LibClone.predictDeterministicAddress(_podImplementation, args, keccak256(args), address(this));
    }

    /// @dev Returns `abi.encode(sender, originalSender, originalSenderType)`.
    /// This is queried by the MessageHubPodV1 or contracts that use MessageHubLibV1.
    receive() external payable {
        assembly ("memory-safe") {
            // The `sender` can be either:
            // - A MessageHubPodV1 that is deployed on-the-fly if the
            //   message was initiated from a non-Ethereum address.
            // - An Ethereum address that initiated the message.
            //
            // The `originalSender` can be either:
            // - A non-Ethereum address.
            // - An Ethereum address that matches `sender`.
            mstore(0x00, tload(_SENDER_TRANSIENT_SLOT))
            mstore(0x20, tload(_ORIGINAL_SENDER_TRANSIENT_SLOT))
            mstore(0x40, tload(_ORIGINAL_SENDER_TYPE_TRANSIENT_SLOT))
            return(0x00, 0x60)
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Withdraws the native token.
    function withdrawNative(address to, uint256 amount) public {
        if (msg.sender != owner()) revert Unauthorized();
        SafeTransferLib.safeTransferETH(to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Creates a sub account.
    function _createSubAccount(bytes32 originalSender, uint256 originalSenderType)
        internal
        returns (address instance)
    {
        bytes memory args = _subAccountArgs(originalSender, originalSenderType);
        (, instance) = LibClone.createDeterministicClone(_podImplementation, args, keccak256(args));
    }

    /// @dev Returns the immutable arguments for the sub account.
    /// `abi.encodePacked(keccak256(abi.encode(originalSender, originalSenderType)), address(this))`.
    function _subAccountArgs(bytes32 originalSender, uint256 originalSenderType)
        internal
        view
        returns (bytes memory result)
    {
        if (originalSender == bytes32(0)) revert OriginalSenderIsZero();
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(0x00, originalSender)
            mstore(0x20, originalSenderType)
            // Address of the mothership.
            mstore(add(result, 0x34), address())
            // Hash of the original sender and sender type.
            mstore(add(result, 0x20), keccak256(0x00, 0x40))
            mstore(result, 0x34) // Store the byte length of the arguments.
            mstore(0x40, add(result, 0x54)) // Allocate memory.
        }
    }

    /// @dev Decodes and forwards the message to the target.
    /// This modifier is to be attached onto the `_lzReceive` function.
    modifier forwardMessage(bytes calldata message) {
        bytes32 originalSender;
        uint256 originalSenderType;
        address target;
        bytes calldata data;

        assembly ("memory-safe") {
            // This is equivalent to
            // `abi.decode(message, (bytes32, uint256, address, bytes))`.
            // This is optimizoored as the hub is on L1.
            originalSender := calldataload(add(message.offset, 0x00))
            originalSenderType := calldataload(add(message.offset, 0x20))
            // Don't need to clean bits, as `call` is agnostic to dirty upper 96 bits.
            target := calldataload(add(message.offset, 0x40))
            let o := add(message.offset, calldataload(add(message.offset, 0x60)))
            data.length := calldataload(o)
            data.offset := add(o, 0x20)
            // Check that all of the data is within bounds.
            if or(lt(message.length, 0x80), gt(add(data.offset, data.length), add(message.offset, message.length))) {
                invalid()
            }
        }

        if (originalSender == bytes32(0)) revert OriginalSenderIsZero();

        address sender = address(uint160(uint256(originalSender)));
        if (originalSenderType != 0) {
            sender = _createSubAccount(originalSender, originalSenderType);
        }

        uint256 toRefund;
        assembly ("memory-safe") {
            let balanceBefore := sub(selfbalance(), callvalue())
            // Disallow reentrancy.
            if tload(_ORIGINAL_SENDER_TRANSIENT_SLOT) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            // Temporarily store the sender and original sender in transient storage.
            tstore(_SENDER_TRANSIENT_SLOT, shr(96, shl(96, sender)))
            tstore(_ORIGINAL_SENDER_TRANSIENT_SLOT, originalSender)
            tstore(_ORIGINAL_SENDER_TYPE_TRANSIENT_SLOT, originalSenderType)

            let m := mload(0x40)
            calldatacopy(m, data.offset, data.length)
            // Calls `target` with `data` and `value`.
            if iszero(call(gas(), target, callvalue(), m, data.length, 0x00, 0x00)) {
                // Bubble up the revert if the call fails.
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            // Reset transient storage.
            tstore(_ORIGINAL_SENDER_TYPE_TRANSIENT_SLOT, 0)
            tstore(_ORIGINAL_SENDER_TRANSIENT_SLOT, 0)
            tstore(_SENDER_TRANSIENT_SLOT, 0)

            toRefund := mul(sub(selfbalance(), balanceBefore), gt(selfbalance(), balanceBefore))
        }
        // If the balance has somehow increased, refunds to the sender.
        if (toRefund != 0) {
            SafeTransferLib.forceSafeTransferETH(sender, toRefund);
        }
        _;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Receives a message from the OApp.
    function _lzReceive(
        Origin calldata, /* origin */
        bytes32, /* guid */
        bytes calldata message,
        address, /* executor */
        bytes calldata /* extraData */
    ) internal override forwardMessage(message) {}

    /// @dev For UUPSUpgradeable. Only the owner can upgrade.
    function _authorizeUpgrade(address) internal virtual override {
        if (msg.sender != owner()) revert Unauthorized();
    }
}
