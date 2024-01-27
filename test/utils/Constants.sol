// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Constants {
    uint256 public constant START_TIME = 1702620000; // 15 DEC 2023 00:00 UTC
    uint256 public constant USERS_FUNDING_AMOUNT = 10 ether;
    uint256 public constant MARKET_OPEN_TIMESTAMP = START_TIME + 7 days;
    uint256 public constant ECDSA_LIMIT = 115792089237316195423570985008687907852837564279074904382605163141518161494337;
    string public constant TEST_NAME = "foobar";
    address public constant TEST_ADDRESS = address(13);
}
