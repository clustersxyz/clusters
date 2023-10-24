// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {SignedWadMath} from "@solmate/utils/SignedWadMath.sol";

contract Pricing {
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;

    constructor() {}

    function getPrice(uint256 p0, uint256 numSeconds) external pure returns (uint256) {
        return p0 * numSeconds / SECONDS_IN_YEAR + (15 * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }
    
    function getDecayMultiplier(uint256 p0, uint256 numSecondsSinceBid) external pure returns (uint256) {
        return exp(-0.6931 * numSecondsSinceBid / SECONDS_IN_YEAR);
    }
}
