// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Origin, OAppReceiverUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppReceiverUpgradeable.sol";

contract ClustersBeta is UUPSUpgradeable, OAppReceiverUpgradeable {
    bytes32 internal constant PLACEHOLDER = bytes32(uint256(1)); // Cheaper to modify a nonzero slot
    bytes32 internal tstoreSender = PLACEHOLDER;

    event Bid(bytes32 from, uint256 amount, bytes32 name);

    error BadBatch();

    error Unauthorized();

    /// UUPSUpgradeable Authentication ///

    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
    }

    /// OAppReceiver Functions ///

    function initialize(address endpoint_, address owner_) external initializer {
        _initializeOAppCore(endpoint_, owner_);
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) internal override {
        tstoreSender = origin.sender;
        address(this).delegatecall(message);
        tstoreSender = PLACEHOLDER;
    }

    /// Core Logic ///

    function placeBid(bytes32 name) external payable {
        bytes32 from = tstoreSender == PLACEHOLDER ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        emit Bid(from, msg.value, name);
    }

    function placeBids(uint256[] calldata amounts, bytes32[] calldata names) external payable {
        uint256 amountTotal = 0;
        bytes32 from = tstoreSender == PLACEHOLDER ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        if (amounts.length != names.length) revert BadBatch();
        for (uint256 i = 0; i < amounts.length; i++) {
            amountTotal += amounts[i];
            emit Bid(from, amounts[i], names[i]);
        }
        if (amountTotal != msg.value) revert BadBatch();
    }
}
