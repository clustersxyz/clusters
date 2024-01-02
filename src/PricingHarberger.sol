// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IPricing, IPricingHarberger} from "clusters/interfaces/IPricingHarberger.sol";
import {FixedPointMathLib as F} from "solady/utils/FixedPointMathLib.sol";
import {console2} from "forge-std/console2.sol";

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
contract PricingHarberger is UUPSUpgradeable, Initializable, Ownable, IPricingHarberger {
    uint256 internal constant SECONDS_IN_MONTH = 30 days;
    uint256 internal constant SECONDS_IN_YEAR = 365 days;
    uint256 internal constant DENOMINATOR = 10_000;
    uint256 internal constant WAD = 1e18;
    int256 internal constant sWAD = 1e18;

    uint256 public constant minAnnualPrice = 0.01 ether;
    uint256 public constant maxPriceBase = 0.02 ether;
    uint256 public constant maxPriceIncrement = 0.01 ether;

    uint256 public protocolDeployTimestamp;

    function initialize(address owner_, uint256 protocolDeployTimestamp_) public initializer {
        _initializeOwner(owner_);
        protocolDeployTimestamp = protocolDeployTimestamp_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// PUBLIC FUNCTIONS ///

    /// @inheritdoc IPricing
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsSinceUpdate)
        public
        view
        returns (uint256, uint256)
    {
        uint256 secondsSinceDeployment = block.timestamp - protocolDeployTimestamp;
        if (lastUpdatedPrice <= minAnnualPrice) {
            // Lower bound
            return (minAnnualPrice * secondsSinceUpdate / SECONDS_IN_YEAR, minAnnualPrice);
        } else if (lastUpdatedPrice >= getMaxPrice(secondsSinceDeployment)) {
            uint256 numYearsUntilMaxPriceWad =
                getMaxIntersection(lastUpdatedPrice, secondsSinceDeployment / SECONDS_IN_YEAR);
            uint256 numSecondsUntilMaxPrice = numYearsUntilMaxPriceWad * SECONDS_IN_YEAR / WAD;

            if (secondsSinceUpdate <= numSecondsUntilMaxPrice) {
                return (getIntegratedMaxPrice(secondsSinceUpdate), getDecayPrice(lastUpdatedPrice, secondsSinceUpdate));
            } else {
                uint256 numYearsUntilMinPriceWad = getMinIntersection(lastUpdatedPrice);
                uint256 numSecondsUntilMinPrice = numYearsUntilMinPriceWad * SECONDS_IN_YEAR / WAD;

                if (secondsSinceUpdate <= numSecondsUntilMinPrice) {
                    uint256 integralPart1 = getIntegratedMaxPrice(numSecondsUntilMaxPrice);
                    uint256 maxPrice1 = getDecayPrice(lastUpdatedPrice, numSecondsUntilMaxPrice);
                    uint256 integralPart2 =
                        getIntegratedDecayPrice(maxPrice1, secondsSinceUpdate - numSecondsUntilMaxPrice);
                    return (integralPart1 + integralPart2, getDecayPrice(lastUpdatedPrice, secondsSinceDeployment));
                } else {
                    uint256 integralPart1 = getIntegratedMaxPrice(numSecondsUntilMaxPrice);
                    uint256 maxPrice1 = getDecayPrice(lastUpdatedPrice, numSecondsUntilMaxPrice);
                    uint256 integralPart2 =
                        getIntegratedDecayPrice(maxPrice1, numSecondsUntilMinPrice - numSecondsUntilMaxPrice);
                    uint256 integralPart3 = minAnnualPrice * secondsSinceUpdate / SECONDS_IN_YEAR;
                    return (integralPart1 + integralPart2 + integralPart3, minAnnualPrice);
                }
            }
        } else {
            // Exponential decay from middle range
            // Calculate time until intersection with min price
            // p0 * e^(t*ln0.5) = minPrice
            // t = ln(minPrice/p0) / ln(0.5)
            uint256 numYearsUntilMinPriceWad =
                uint256(F.rawSDivWad(F.lnWad(int256(F.rawDivWad(minAnnualPrice, lastUpdatedPrice))), F.lnWad(0.5e18)));
            uint256 numSecondsUntilMinPrice = numYearsUntilMinPriceWad * SECONDS_IN_YEAR / WAD;

            if (secondsSinceUpdate <= numSecondsUntilMinPrice) {
                // Return simple exponential decay integral
                return (
                    getIntegratedDecayPrice(lastUpdatedPrice, secondsSinceUpdate),
                    getDecayPrice(lastUpdatedPrice, secondsSinceUpdate)
                );
            } else {
                (uint256 simpleMinLeftover,) =
                    getIntegratedPrice(minAnnualPrice, secondsSinceUpdate - numSecondsUntilMinPrice);
                return (
                    getIntegratedDecayPrice(lastUpdatedPrice, numSecondsUntilMinPrice) + simpleMinLeftover,
                    minAnnualPrice
                );
            }
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @return yearsUntilIntersectionWad
    function getMaxIntersection(uint256 p, uint256 yearsSinceDeploymentWad) internal pure returns (uint256) {
        // Calculate time until lastUpdatedPrice exponential decay intersects with max price positive slope line
        // Solve pe^(t*ln(0.5)) = 0.02 + 0.01*(years+t)
        // https://www.wolframalpha.com/input?i=pe%5E%28x*ln%280.5%29%29+%3D+0.02+%2B+0.01y+%2B+0.01x%2C+solve+for+x
        // Copy paste select 0 branch of Lambert W
        // https://www.wolframalpha.com/input?i=-2+-+1+y+%2B+1.4427+ProductLog%280%2C+%28196722032+e%5E%28%2849180508+%282+%2B+y%29%29%2F70952475%29+p%29%2F2838099%29
        // Then simplify the large fractions
        // https://www.wolframalpha.com/input?i=-2+-+1+y+%2B+1.4427+ProductLog%280%2C+%2869.3147e%5E%280.693147%282+%2B+y%29%29+p%29%29
        // Plot at
        // https://www.wolframalpha.com/input?i=-2+-+y+%2B+1.4427+ProductLog%280%2C+%2869.3147e%5E%280.693147%282+%2B+y%29%29+p%29%29%2C+plot+for+p+in+%5B0%2C+1%5D+with+y%3D10
        // Looks correct, p=x=0.02 yields 0, meaning starting price of 0.02 eth intersects with max price at time 0
        // p=x=1 yields ~4, meaning starting price of 1 eth gets cut in half 4 times in 4 years landing at 0.061
        // intersecting with 0.02 + 0.01*4years

        return uint256(
            F.rawSMulWad(
                1.4427e18,
                F.lambertW0Wad(
                    F.rawSMulWad(
                        int256(F.rawMulWad(69.3147e18, p)),
                        F.expWad(int256(F.mulWad(0.693147e18, 2 * WAD + yearsSinceDeploymentWad)))
                    )
                )
            )
        ) - 2 * WAD - yearsSinceDeploymentWad;
    }

    /// @return yearsUntilIntersectionWad
    function getMinIntersection(uint256 p) internal pure returns (uint256) {
        return uint256(F.rawSDivWad(F.lnWad(int256(F.rawDivWad(minAnnualPrice, p))), F.lnWad(0.5e18)));
    }

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
        return F.rawMulWad(p0, uint256(F.rawSDivWad(int256(getDecayMultiplier(numSeconds)) - sWAD, F.lnWad(0.5e18))));
    }

    /// @notice The annual decayed price at an instantaneous point in time, derivative of getIntegratedDecayPrice
    function getDecayPrice(uint256 p0, uint256 numSeconds) internal pure returns (uint256) {
        return F.rawMulWad(p0, getDecayMultiplier(numSeconds));
    }

    /// @notice Implements e^(ln(0.5)x) ~= e^(-0.6931x) which cuts the number in half every year for exponential decay
    /// @dev Since this will be <1, returns a wad with 18 decimals
    function getDecayMultiplier(uint256 numSeconds) internal pure returns (uint256) {
        return uint256(F.expWad(F.lnWad(0.5e18) * int256(numSeconds) / int256(SECONDS_IN_YEAR)));
    }

    /// @notice Current adjusts quadratically up to bid price, capped at 1 month duration
    function getPriceAfterBid(uint256 p0, uint256 pBid, uint256 bidLengthInSeconds) internal pure returns (uint256) {
        if (p0 >= pBid) return p0;
        if (bidLengthInSeconds >= SECONDS_IN_MONTH) return pBid;
        uint256 wadMonths = toWadUnsafe(bidLengthInSeconds) / SECONDS_IN_MONTH;
        return p0 + F.rawMulWad(pBid - p0, F.rawMulWad(wadMonths, wadMonths));
    }

    function toWadUnsafe(uint256 x) internal pure returns (uint256) {
        return F.rawMul(WAD, x);
    }
}
