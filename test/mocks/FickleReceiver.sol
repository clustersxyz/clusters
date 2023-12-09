// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract FickleReceiver {
    bool isReceiving;

    constructor() {}

    function flipflop() external {
        isReceiving = !isReceiving;
    }

    function deposit() external payable {
        return;
    }

    receive() external payable {
        if (isReceiving) revert();
    }
}
