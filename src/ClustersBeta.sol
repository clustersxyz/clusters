// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Origin, OAppReceiverUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppReceiverUpgradeable.sol";

contract ClustersBeta is UUPSUpgradeable, OAppReceiverUpgradeable {
    event Bid(bytes32 from, uint256 amount, bytes32 name);
    event Bid(bytes32 from, uint256 amount, bytes32 name, bytes32 referralAddress);

    error BadBatch();
    error BadDelegatecall();
    error Unauthorized();

    /// UUPSUpgradeable Authentication ///

    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
    }

    /// OAppReceiver Functions ///

    function initialize(address endpoint_, address owner_) external initializer {
        _initializeOAppCore(endpoint_, owner_);
    }

    function reinitialize() external reinitializer(2) {
        // Unset placeholder 1 val from storage slot 0x2 onchain where tstoreSender used to live pre-dencun
        assembly ("memory-safe") {
            sstore(2, 0)
        }
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) internal override {
        (bytes32 msgsender, bytes memory calldata_) = abi.decode(message, (bytes32, bytes));
        assembly ("memory-safe") {
            tstore(0, msgsender)
        }
        (bool success,) = address(this).delegatecall(calldata_);
        if (!success) revert BadDelegatecall();
        assembly ("memory-safe") {
            tstore(0, 0)
        }
    }

    /// Core Logic ///

    function placeBid(bytes32 name) external payable {
        bytes32 tstoreSender;
        assembly ("memory-safe") {
            tstoreSender := tload(0)
        }
        bytes32 from = tstoreSender == 0 ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        emit Bid(from, msg.value, name);
    }

    function placeBids(uint256[] calldata amounts, bytes32[] calldata names) external payable {
        bytes32 tstoreSender;
        assembly ("memory-safe") {
            tstoreSender := tload(0)
        }
        bytes32 from = tstoreSender == 0 ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        if (amounts.length != names.length) revert BadBatch();
        uint256 amountTotal = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            amountTotal += amounts[i];
            emit Bid(from, amounts[i], names[i]);
        }
        if (amountTotal != msg.value) revert BadBatch();
    }

    function placeBid(bytes32 name, bytes32 referralAddress) external payable {
        bytes32 tstoreSender;
        assembly ("memory-safe") {
            tstoreSender := tload(0)
        }
        bytes32 from = tstoreSender == 0 ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        emit Bid(from, msg.value, name, referralAddress);
    }

    function placeBids(uint256[] calldata amounts, bytes32[] calldata names, bytes32 referralAddress)
        external
        payable
    {
        bytes32 tstoreSender;
        assembly ("memory-safe") {
            tstoreSender := tload(0)
        }
        bytes32 from = tstoreSender == 0 ? bytes32(uint256(uint160(msg.sender))) : tstoreSender;
        if (amounts.length != names.length) revert BadBatch();
        uint256 amountTotal = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            amountTotal += amounts[i];
            emit Bid(from, amounts[i], names[i], referralAddress);
        }
        if (amountTotal != msg.value) revert BadBatch();
    }

    function withdraw(address payable to_, uint256 amount) external {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
        to_.call{value: amount}("");
    }
}
