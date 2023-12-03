// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {PricingHarbergerHarness} from "./harness/PricingHarbergerHarness.sol";

contract PricingHarbergerTest is Test {
    PricingHarbergerHarness public pricing;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    function setUp() public {
        pricing = new PricingHarbergerHarness();
        minPrice = pricing.minAnnualPrice();
    }

    function testDecayMultiplier() public {
        int256 decay = pricing.exposed_getDecayMultiplier(730 days);
        assertEq(decay, int256(0.25e18 - 1)); // Tiny error tolerance is okay
    }

    function testIntegratedDecayPrice() public {
        uint256 spent = pricing.exposed_getIntegratedDecayPrice(1 ether, 730 days);
        assertEq(spent, 1082021280666722556); // 1.08 ether over 2 years
    }

    function testIntegratedPriceSimpleMin() public {
        (uint256 simpleMinSpent, uint256 simpleMinPrice) =
            pricing.getIntegratedPrice(minPrice, 730 days, secondsAfterCreation);
        assertEq(simpleMinSpent, 2 * minPrice);
        assertEq(simpleMinPrice, minPrice);
    }

    function testIntegratedPriceSimpleDecay() public {
        (uint256 simpleDecaySpent, uint256 simpleDecayPrice) =
            pricing.getIntegratedPrice(1 ether, 730 days, secondsAfterCreation);
        assertEq(simpleDecaySpent, 1082021280666722556); // 1.08 ether over 2 years
        assertEq(simpleDecayPrice, 0.25e18 - 1); // Cut in half every year, now a quarter of start price
    }

    function testIntegratedPriceSimpleDecay2() public {
        (uint256 simpleDecaySpent2, uint256 simpleDecayPrice2) =
            pricing.getIntegratedPrice(1 ether, 209520648, secondsAfterCreation);
        assertEq(simpleDecaySpent2, 1428268090226162139); // 1.42 ether over 6.64 years
        assertEq(simpleDecayPrice2, 10000000175998132); // ~0.01 price after 6.64 years
    }

    function testIntegratedPriceComplexDecay() public {
        (uint256 complexDecaySpent, uint256 complexDecayPrice) =
            pricing.getIntegratedPrice(1 ether, 10 * 365 days, secondsAfterCreation);
        assertEq(complexDecaySpent, 1461829528582326522); // 1.42 ether over 6.6 years then 0.03 ether over 3 years
        assertEq(complexDecayPrice, minPrice);
    }

    function testIntegratedPriceSimpleMax() public {
        (uint256 simpleMaxSpent, uint256 simpleMaxPrice) = pricing.getIntegratedPrice(1 ether, 365 days, 365 days);
        assertEq(simpleMaxSpent, 0.025 ether);
        assertEq(simpleMaxPrice, 0.5 ether - 1); // Actual price has decayed by half before being truncated by max
    }

    function testIntegratedPriceMaxToMiddleRange() public {
        (uint256 maxToMiddleSpent, uint256 maxToMiddlePrice) =
            pricing.getIntegratedPrice(0.025 ether, 365 days, 365 days);
        assertEq(maxToMiddleSpent, 18033688011112042); // 0.018 ether for 1 year that dips from max into middle
        assertEq(maxToMiddlePrice, 0.0125 ether - 1);
    }

    function testIntegratedPriceMaxToMinRange() public {
        (uint256 maxToMinSpent, uint256 maxToMinPrice) = pricing.getIntegratedPrice(0.025 ether, 730 days, 730 days);
        assertEq(maxToMinSpent, 28421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);

        (maxToMinSpent, maxToMinPrice) = pricing.getIntegratedPrice(0.025 ether, 3 * 365 days, 3 * 365 days);
        assertEq(maxToMinSpent, 38421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);
    }

    function testPriceAfterBid() public {
        uint256 newPrice = pricing.exposed_getPriceAfterBid(1 ether, 2 ether, 0);
        assertEq(newPrice, 1 ether);

        newPrice = pricing.exposed_getPriceAfterBid(1 ether, 2 ether, 15 days);
        assertEq(newPrice, 1.25 ether);

        newPrice = pricing.exposed_getPriceAfterBid(1 ether, 2 ether, 30 days);
        assertEq(newPrice, 2 ether);
    }
}
