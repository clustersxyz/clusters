// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {toWadUnsafe, wadExp, wadLn, unsafeWadMul} from "solmate/utils/SignedWadMath.sol";

/// @notice A stateless computation library for price, bids, decays, etc
/// @dev All state is stored in clusters so we can replace the Pricing module while providing guarantees to existing
/// holders
contract Pricing {
    uint256 internal constant SECONDS_IN_MONTH = 30 days;
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;

    constructor() {}

    function getPrice(uint256 p0, uint256 numSeconds) external pure returns (uint256) {
        return p0 * numSeconds / SECONDS_IN_YEAR + (15 * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }

    /// @notice Implements e^(ln(0.5)x) ~= e^(-0.6931x) which cuts the number in half every year for exponential decay
    /// @dev Since this will be <1, returns a wad with 18 decimals
    function getDecayMultiplier(uint256 p0, uint256 numSecondsSinceBid) external pure returns (int256) {
        return wadExp(wadLn(0.5e18) * int256(numSecondsSinceBid) / int256(SECONDS_IN_YEAR));
    }

    /// @notice Should boost the annual price to 1/12th of (bidAmount * months)
    function getBidMultiplier(uint256 p0, uint256 pBid, uint256 bidLengthInSeconds) external pure returns (int256) {
        int256 wadMonths = toWadUnsafe(bidLengthInSeconds) / int256(SECONDS_IN_MONTH);
        int256 targetPrice = unsafeWadMul(wadMonths, int256(pBid));
    }
}
