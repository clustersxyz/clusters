// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract Clusters {
    error AlreadyPurchased(string data);
    event Purchase(address indexed purchaser, uint256 indexed payment, string indexed data);

    struct Buy {
        address purchaser;
        uint256 payment;
    }

    mapping(string data => Buy) public buys;

    constructor() {}

    function executeBuy(string memory data) public payable {
        if (buys[data].purchaser != address(0)) revert AlreadyPurchased(data);
        buys[data] = Buy({ purchaser: msg.sender, payment: msg.value });
        emit Purchase(msg.sender, msg.value, data);
    }
}