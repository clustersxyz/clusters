// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {Lambert} from "../src/Lambert.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;
    Lambert public lambert;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
        lambert = new Lambert();
        minPrice = pricing.minAnnualPrice();
    }

    function testDecayMultiplier() public {
        int256 decay = pricing.getDecayMultiplier(730 days);
        assertEq(decay, int256(0.25e18 - 1)); // Tiny error tolerance is okay
    }

    function testIntegratedDecayPrice() public {
        uint256 spent = pricing.getIntegratedDecayPrice(1 ether, 730 days);
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
        (uint256 simpleMaxSpent, uint256 simpleMaxPrice) =
            pricing.getIntegratedPrice(1 ether, 365 days, secondsAfterCreation);
        assertEq(simpleMaxSpent, simpleMaxSpent);
    }

    function testLambert() public {
        vm.expectRevert("must be > 1/e");
        lambert.W0(0);
        vm.expectRevert("must be > 1/e");
        lambert.W0(367879441171442322);

        // W(1/e) ~= 0.278
        assertEq(lambert.W0(367879441171442322 + 1), 278464542761073797);

        // W(0.5) ~= 0.351
        assertEq(lambert.W0(0.5e18), 351703661682451427);

        // W(e) == 1
        assertEq(lambert.W0(2718281828459045235), 999997172107599752);

        // W(3) ~= 1.0499
        assertEq(lambert.W0(3e18), 1049906379855897971);

        // W(10) ~= 1.7455, approx is 1.830768336445553094
        assertEq(lambert.W0(10e18), 1830768336445553094);
    }
}
