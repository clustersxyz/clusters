// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {toWadUnsafe, wadExp, wadLn, unsafeWadMul, unsafeWadDiv} from "solmate/utils/SignedWadMath.sol";

/*
ECONOMIC MODEL:
annual price: f'(n) = p0 + 15n
integral of annual price, registration fee for n years: f(n) = p0*n + 7.5n^2

*/

/// @notice A stateless computation library for price, bids, decays, etc
/// @dev All state is stored in clusters so we can replace the Pricing module while providing guarantees to existing
/// holders
contract Pricing {
    uint256 internal constant SECONDS_IN_MONTH = 30 days;
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;

    uint256 public minAnnualPrice = 0.01 ether;

    constructor() {}

    /// @notice If no bids occur and name price starts at p0, how many seconds until ethAmount runs out?
    function getMaxDuration(uint256 p0, uint256 ethAmount) external returns (int256) {
        if (p0 <= minAnnualPrice) {
            return unsafeWadDiv(unsafeWadMul(toWadUnsafe(SECONDS_IN_YEAR), toWadUnsafe(ethAmount)), toWadUnsafe(p0));
        } else {
            return 0;
        }
    }

    /// @notice The amount of eth that's been spent on a name since last update
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsAfterUpdate) public view returns (uint256) {
        if (lastUpdatedPrice <= minAnnualPrice) return minAnnualPrice * secondsAfterUpdate / SECONDS_IN_YEAR;
        else return 0;
    }

    /// @notice The annual max price integrated over its duration,
    function getIntegratedMaxPrice(uint256 p0, uint256 numSeconds) public pure returns (uint256) {
        return p0 * numSeconds / SECONDS_IN_YEAR + (15 * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }

    function getMaxPrice(uint256 p0, uint256 numSeconds) public pure returns (uint256) {
        return p0 + (15 * numSeconds) / (2 * SECONDS_IN_YEAR);
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
