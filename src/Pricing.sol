// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract Pricing {
    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    constructor() {}

    function getPrice(uint256 p0, uint256 numSeconds) external pure returns (uint256) {
        return p0 * numSeconds / SECONDS_IN_YEAR + (15 * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }
}
