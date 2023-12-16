// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";

contract PricingHarberger_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    uint256 secondsSinceDeployment = 1000 * 365 days;

    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
    }

    function testDecayMultiplier() public {
        uint256 decay = pricingHarberger.exposed_getDecayMultiplier(730 days);
        assertEq(decay, 0.25e18 - 1); // Tiny error tolerance is okay
    }

    function testMaxIntersectionZeroSecondsSinceDeployment() public {
        uint256 intersectionBasic = pricingHarberger.exposed_getMaxIntersection(0.02 ether, 0e18);
        assertLt(intersectionBasic, 9e12); // Tiny error tolerance

        uint256 intersectionOne = pricingHarberger.exposed_getMaxIntersection(1 ether, 0e18);
        assertEq(intersectionOne, 4047534052094804142); // 4.04 years

        uint256 intersectionHundred = pricingHarberger.exposed_getMaxIntersection(100 ether, 0e18);
        assertEq(intersectionHundred, 9735009655744918055); // 9.7 years
    }

    function testMaxIntersectionTenYearsSinceDeployment() public {
        // TODO: Is numerical drift as the yearsSinceDeployment increases an issue?
        uint256 intersectionBasic = pricingHarberger.exposed_getMaxIntersection(0.12 ether, 10e18);
        assertLt(intersectionBasic, 9e13);

        uint256 intersectionOne = pricingHarberger.exposed_getMaxIntersection(1 ether, 10e18);
        assertEq(intersectionOne, 2760261962592581821); // 2.7 years

        uint256 intersectionHundred = pricingHarberger.exposed_getMaxIntersection(100 ether, 10e18);
        assertEq(intersectionHundred, 8902202613552457583); // 8.7 years
    }

    function testIntegratedDecayPrice() public {
        uint256 spent = pricingHarberger.exposed_getIntegratedDecayPrice(1 ether, 730 days);
        assertEq(spent, 1082021280666722556); // 1.08 ether over 2 years
    }

    function testIntegratedPriceSimpleMin() public {
        (uint256 simpleMinSpent, uint256 simpleMinPrice) = pricingHarberger.getIntegratedPrice(minPrice, 730 days);
        assertEq(simpleMinSpent, 2 * minPrice);
        assertEq(simpleMinPrice, minPrice);
    }

    function testIntegratedPriceSimpleDecay() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 simpleDecaySpent, uint256 simpleDecayPrice) = pricingHarberger.getIntegratedPrice(1 ether, 730 days);
        assertEq(simpleDecaySpent, 1082021280666722556); // 1.08 ether over 2 years
        assertEq(simpleDecayPrice, 0.25e18 - 1); // Cut in half every year, now a quarter of start price
    }

    function testIntegratedPriceSimpleDecay2() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 simpleDecaySpent2, uint256 simpleDecayPrice2) = pricingHarberger.getIntegratedPrice(1 ether, 209520648);
        assertEq(simpleDecaySpent2, 1428268090226162139); // 1.42 ether over 6.64 years
        assertEq(simpleDecayPrice2, 10000000175998132); // ~0.01 price after 6.64 years
    }

    /// @dev Trying to recreate the overflow problem with large lastUpdatedPrice value
    function testIntegratedPriceSimpleDecay3() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 simpleDecaySpent3, uint256 simpleDecayPrice3) =
            pricingHarberger.getIntegratedPrice(100 ether, 365 days);
    }

    function testIntegratedPriceComplexDecay() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 complexDecaySpent, uint256 complexDecayPrice) =
            pricingHarberger.getIntegratedPrice(1 ether, 10 * 365 days);
        assertEq(complexDecaySpent, 1461829528582326522); // 1.42 ether over 6.6 years then 0.03 ether over 3 years
        assertEq(complexDecayPrice, minPrice);
    }

    function testIntegratedPriceSimpleMax() public {
        (uint256 simpleMaxSpent, uint256 simpleMaxPrice) = pricingHarberger.getIntegratedPrice(1 ether, 365 days);
        assertEq(simpleMaxSpent, 0.025 ether);
        assertEq(simpleMaxPrice, 0.5 ether - 1); // Actual price has decayed by half before being truncated by max
    }

    function testIntegratedPriceMaxToMiddleRange() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 maxToMiddleSpent, uint256 maxToMiddlePrice) =
            pricingHarberger.getIntegratedPrice(0.025 ether, 365 days);
        assertEq(maxToMiddleSpent, 18033688011112042); // 0.018 ether for 1 year that dips from max into middle
        assertEq(maxToMiddlePrice, 0.0125 ether - 1);
    }

    function testIntegratedPriceMaxToMinRange() public {
        vm.warp(block.timestamp + secondsSinceDeployment); // Simulate large secondsSinceDeployment value
        (uint256 maxToMinSpent, uint256 maxToMinPrice) = pricingHarberger.getIntegratedPrice(0.025 ether, 730 days);
        assertEq(maxToMinSpent, 28421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);

        (maxToMinSpent, maxToMinPrice) = pricingHarberger.getIntegratedPrice(0.025 ether, 3 * 365 days);
        assertEq(maxToMinSpent, 38421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);
    }

    function testPriceAfterBid() public {
        uint256 newPrice = pricingHarberger.exposed_getPriceAfterBid(1 ether, 2 ether, 0);
        assertEq(newPrice, 1 ether);

        newPrice = pricingHarberger.exposed_getPriceAfterBid(1 ether, 2 ether, 15 days);
        assertEq(newPrice, 1.25 ether);

        newPrice = pricingHarberger.exposed_getPriceAfterBid(1 ether, 2 ether, 30 days);
        assertEq(newPrice, 2 ether);
    }
}
