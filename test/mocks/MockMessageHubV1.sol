// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/MessageHubV1.sol";

contract MockMessageHubV1 is MessageHubV1 {
    function createSubAccount(bytes32 originalSender, uint256 senderType) public returns (address) {
        return _createSubAccount(originalSender, senderType);
    }

    function forward(bytes calldata message) public payable forwardMessage(message) {}
}
