// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract Pricing {

    constructor() {}

    function getPrice(uint256 p0, uint256 numSeconds) external pure returns (uint256) {
        return (p0 * 15 * numSeconds) / (2 * (52 weeks));
    }
}
