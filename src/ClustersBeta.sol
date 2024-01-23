// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";

contract ClustersBeta is UUPSUpgradeable {
    event Bid(address from, uint256 amount, bytes32 name);

    error BadBatch();

    error Unauthorized();

    // Authentication for UUPS
    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
    }

    function placeBid(bytes32 name) public payable {
        emit Bid(msg.sender, msg.value, name);
    }

    function placeBids(uint256[] calldata amounts, bytes32[] calldata names) public payable {
        uint256 amountTotal = 0;
        if (amounts.length != names.length) revert BadBatch();
        for (uint256 i = 0; i < amounts.length; i++) {
            amountTotal += amounts[i];
            emit Bid(msg.sender, amounts[i], names[i]);
        }
        if (amountTotal != msg.value) revert BadBatch();
    }
}
