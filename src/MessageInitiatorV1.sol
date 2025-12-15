// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
import {
    OAppSenderUpgradeable, MessagingFee
} from "layerzero-oapp/contracts/oapp-upgradeable/OAppSenderUpgradeable.sol";

/// @title MessageInitiatorV1
/// @notice Generalized contract for sending messages to `MessageHubV1`.
contract MessageInitiatorV1 is UUPSUpgradeable, OAppSenderUpgradeable {
    using OptionsBuilder for bytes;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The storage struct for the contract.
    struct MessageInitiatorStorage {
        uint32 dstEid;
    }

    /// @dev Returns the storage struct for the contract.
    function _getMessageInitiatorStorage() internal pure returns (MessageInitiatorStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.MessageInitiatorStorage")))`.
            $.slot := 0xf707b7e13707881ad4 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when the destination endpoint ID is set.
    event DstEidSet(uint32 eid);

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

    /// @dev Sends a message.
    function sendWithDefaultOptions(address target, bytes memory data, uint256 gas, uint256 value) public payable {
        send(target, data, defaultOptions(gas, value));
    }

    /// @dev Sends a message.
    function send(address target, bytes memory data, bytes memory options) public payable {
        bytes memory encoded = abi.encode(msg.sender, 0, target, data);
        _lzSend(dstEid(), encoded, options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the Layerzero destination endpoint ID.
    function dstEid() public view returns (uint32) {
        return _getMessageInitiatorStorage().dstEid;
    }

    /// @dev Returns the native fee for sending a message.
    function quoteWithDefaultOptions(address target, bytes memory data, uint256 gas, uint256 value)
        public
        view
        returns (uint256)
    {
        return quote(target, data, defaultOptions(gas, value));
    }

    /// @dev Returns the native fee for sending a message.
    function quote(address target, bytes memory data, bytes memory options) public view returns (uint256) {
        bytes memory encoded = abi.encode(keccak256(abi.encode(address(this))), 0, target, data);
        return _quote(dstEid(), encoded, options, false).nativeFee;
    }

    /// @dev Returns the default options that encodes `gas` and `value`.
    function defaultOptions(uint256 gas, uint256 value) public pure returns (bytes memory) {
        if (gas | value >= 1 << 128) revert();
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(gas), uint128(value));
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Enables the owner to set the destination endpoint ID.
    function setDstEid(uint32 eid) public onlyOwner {
        _getMessageInitiatorStorage().dstEid = eid;
        emit DstEidSet(eid);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For UUPSUpgradeable. Only the owner can upgrade.
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}
}
