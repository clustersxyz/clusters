// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {toWadUnsafe, wadExp, wadLn} from "solmate/utils/SignedWadMath.sol";

contract Pricing {
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;

    constructor() {}

    function getPrice(uint256 p0, uint256 numSeconds) external pure returns (uint256) {
        return p0 * numSeconds / SECONDS_IN_YEAR + (15 * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }
    
    /// @notice Implements e^(-ln(0.5)x) ~= e^(-0.6931x) which cuts the number in half every year for exponential decay
    /// @dev Watch out for rounding errors here if multiplier is <0.5
    function getDecayMultiplier(uint256 p0, uint256 numSecondsSinceBid) external pure returns (int256) {
        return wadExp(wadLn(0.5e18) * int256(numSecondsSinceBid) / int256(SECONDS_IN_YEAR));
    }
}
