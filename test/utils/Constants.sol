// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract Constants {
    uint256 public constant START_TIME = 1702620000; // 15 DEC 2023 00:00 UTC
    uint256 public constant USERS_FUNDING_AMOUNT = 10 ether;
    uint256 public constant MARKET_OPEN_TIMESTAMP = START_TIME + 7 days;
}
