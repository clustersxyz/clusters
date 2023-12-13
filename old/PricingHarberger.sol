// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {toWadUnsafe, wadExp, wadLn, unsafeWadMul, unsafeWadDiv} from "../lib/solmate/src/utils/SignedWadMath.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {IPricing} from "./IPricing.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/*
ECONOMIC MODEL:
min annual price: 0.01 ether
max annual price: 0.02 ether + 0.01 ether per year
max annual price: f'(n) = 0.02 + 0.01n
integral of max annual price, registration fee for n years: f(n) = 0.02n + 0.005n^2

prices follow an exponential decay: pe^(y*ln(0.5)) where y is the fractional number of years since last bid and p is
price at last bid
bids increase price to bid amount in 1 month, price += ((bidPrice - oldPrice) * months^2) and simply price = bidPrice
for months >= 1
*/

/// @notice A stateless computation library for price, bids, decays, etc
/// @dev All state is stored in clusters so we can replace the Pricing module while providing guarantees to existing
/// holders
contract PricingHarberger is IPricing {
    uint256 internal constant SECONDS_IN_MONTH = 30 days;
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;

    uint256 public constant minAnnualPrice = 0.01 ether;
    uint256 public constant maxPriceBase = 0.02 ether;
    uint256 public constant maxPriceIncrement = 0.01 ether;

    /// PUBLIC FUNCTIONS ///

    /// @notice The amount of eth that's been spent on a name since last update
    /// @param lastUpdatedPrice Can be greater than max price, used to calculate decay times
    /// @param secondsAfterUpdate How many seconds it's been since lastUpdatedPrice
    /// @return spent How much eth has been spent
    /// @return price The current un-truncated price, which can be greater than maxPrice
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsAfterUpdate, uint256 secondsAfterCreation)
        public
        pure
        returns (uint256, uint256)
    {
        if (lastUpdatedPrice <= minAnnualPrice) {
            // Lower bound
            return (minAnnualPrice * secondsAfterUpdate / SECONDS_IN_YEAR, minAnnualPrice);
        } else if (lastUpdatedPrice >= getMaxPrice(secondsAfterCreation)) {
            // Upper bound
            // Calculate time until intersection with max price
            // Then calculate time until intersection with min price
            // https://www.wolframalpha.com/input?i=pe%5E%28x*ln%280.5%29%29+%3D+p+%2B+15x%2C+solve+for+x
            // https://www.wolframalpha.com/input?i=pe%5E%28x*ln%280.5%29%29+%3D+p+%2B+0.01x%2C+solve+for+x
            // https://www.wolframalpha.com/input?i=pe%5E%28x*ln%280.5%29%29+%3D+p+%2B+0.01%28x%2Bt%29%2C+solve+for+x
            // Intersection of pe^(t*ln(0.5)) = p + 15t
            // t = 1.4427 * W0(0.49e^(0.49p)) - 2p/30
            // https://www.wolframalpha.com/input?i=plot+1.4427+*+lambert+w+function%280.49e%5E%280.49x%29%29+-+2x%2F30+for+x+in+%5B0%2C+10%5D
            // uint256 secondsBeforeUpdate = secondsAfterCreation - secondsAfterUpdate;
            int256 numYearsUntilMaxPrice = unsafeWadMul(
                1.4427e18,
                FixedPointMathLib.lambertW0Wad(
                    unsafeWadMul(69.314e18, wadExp(unsafeWadMul(69.314e18, int256(lastUpdatedPrice))))
                )
            ) - 100 * int256(lastUpdatedPrice);
            uint256 numSecondsUntilMaxPrice =
                uint256(unsafeWadMul(numYearsUntilMaxPrice, toWadUnsafe(SECONDS_IN_YEAR)) / 1e18);

            if (secondsAfterUpdate <= numSecondsUntilMaxPrice) {
                return (getIntegratedMaxPrice(secondsAfterUpdate), getDecayPrice(lastUpdatedPrice, secondsAfterUpdate));
            } else {
                int256 numYearsUntilMinPrice = unsafeWadDiv(
                    wadLn(unsafeWadDiv(toWadUnsafe(minAnnualPrice), toWadUnsafe(lastUpdatedPrice))), wadLn(0.5e18)
                );
                uint256 numSecondsUntilMinPrice =
                    uint256(unsafeWadMul(numYearsUntilMinPrice, toWadUnsafe(SECONDS_IN_YEAR)) / 1e18);

                if (secondsAfterUpdate <= numSecondsUntilMinPrice) {
                    uint256 integralPart1 = getIntegratedMaxPrice(numSecondsUntilMaxPrice);
                    uint256 maxPrice1 = getDecayPrice(lastUpdatedPrice, numSecondsUntilMaxPrice);
                    uint256 integralPart2 =
                        getIntegratedDecayPrice(maxPrice1, secondsAfterUpdate - numSecondsUntilMaxPrice);
                    return (integralPart1 + integralPart2, getDecayPrice(lastUpdatedPrice, secondsAfterCreation));
                } else {
                    uint256 integralPart1 = getIntegratedMaxPrice(numSecondsUntilMaxPrice);
                    uint256 maxPrice1 = getDecayPrice(lastUpdatedPrice, numSecondsUntilMaxPrice);
                    uint256 integralPart2 =
                        getIntegratedDecayPrice(maxPrice1, numSecondsUntilMinPrice - numSecondsUntilMaxPrice);
                    uint256 integralPart3 = minAnnualPrice * secondsAfterUpdate / SECONDS_IN_YEAR;
                    return (integralPart1 + integralPart2 + integralPart3, minAnnualPrice);
                }
            }
        } else {
            // Exponential decay from middle range
            // Calculate time until intersection with min price
            // p0 * e^(t*ln0.5) = minPrice
            // t = ln(minPrice/p0) / ln(0.5)
            int256 numYearsUntilMinPrice = unsafeWadDiv(
                wadLn(unsafeWadDiv(toWadUnsafe(minAnnualPrice), toWadUnsafe(lastUpdatedPrice))), wadLn(0.5e18)
            );
            uint256 numSecondsUntilMinPrice =
                uint256(unsafeWadMul(numYearsUntilMinPrice, toWadUnsafe(SECONDS_IN_YEAR)) / 1e18);

            if (secondsAfterUpdate <= numSecondsUntilMinPrice) {
                // Return simple exponential decay integral
                return (
                    getIntegratedDecayPrice(lastUpdatedPrice, secondsAfterUpdate),
                    getDecayPrice(lastUpdatedPrice, secondsAfterUpdate)
                );
            } else {
                (uint256 simpleMinLeftover,) = getIntegratedPrice(
                    minAnnualPrice, secondsAfterUpdate - numSecondsUntilMinPrice, secondsAfterCreation
                );
                return (
                    getIntegratedDecayPrice(lastUpdatedPrice, numSecondsUntilMinPrice) + simpleMinLeftover,
                    minAnnualPrice
                );
            }
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice The annual max price integrated over its duration
    function getIntegratedMaxPrice(uint256 numSeconds) internal pure returns (uint256) {
        return maxPriceBase * numSeconds / SECONDS_IN_YEAR
            + (maxPriceIncrement * numSeconds ** 2) / (2 * SECONDS_IN_YEAR ** 2);
    }

    /// @notice The annual max price at an instantaneous point in time, derivative of getIntegratedMaxPrice
    function getMaxPrice(uint256 numSeconds) internal pure returns (uint256) {
        return maxPriceBase + (maxPriceIncrement * numSeconds) / SECONDS_IN_YEAR;
    }

    /// @notice The integral of the annual price while it's exponentially decaying over `numSeconds` starting at p0
    function getIntegratedDecayPrice(uint256 p0, uint256 numSeconds) internal pure returns (uint256) {
        return uint256(
            unsafeWadMul(int256(p0), unsafeWadDiv(getDecayMultiplier(numSeconds) - toWadUnsafe(1), wadLn(0.5e18)))
        );
    }

    /// @notice The annual decayed price at an instantaneous point in time, derivative of getIntegratedDecayPrice
    function getDecayPrice(uint256 p0, uint256 numSeconds) internal pure returns (uint256) {
        return uint256(unsafeWadMul(int256(p0), getDecayMultiplier(numSeconds)));
    }

    /// @notice Implements e^(ln(0.5)x) ~= e^(-0.6931x) which cuts the number in half every year for exponential decay
    /// @dev Since this will be <1, returns a wad with 18 decimals
    function getDecayMultiplier(uint256 numSeconds) internal pure returns (int256) {
        return wadExp(wadLn(0.5e18) * int256(numSeconds) / int256(SECONDS_IN_YEAR));
    }

    /// @notice Current adjusts quadratically up to bid price, capped at 1 month duration
    function getPriceAfterBid(uint256 p0, uint256 pBid, uint256 bidLengthInSeconds) internal pure returns (uint256) {
        if (p0 >= pBid) return p0;
        if (bidLengthInSeconds >= SECONDS_IN_MONTH) return pBid;
        int256 wadMonths = toWadUnsafe(bidLengthInSeconds) / int256(SECONDS_IN_MONTH);
        return p0 + uint256(unsafeWadMul(int256(pBid - p0), unsafeWadMul(wadMonths, wadMonths)));
    }
}
