// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
    }

    function testDecayMultiplier() public {
        int256 decay = pricing.getDecayMultiplier(730 days);
        assertEq(decay, int256(0.25e18 - 1)); // Tiny error tolerance is okay
    }

    function testIntegratedDecayPrice() public {
        uint256 spent = pricing.getIntegratedDecayPrice(1 ether, 730 days);
        assertEq(spent, 1082021280666722556); // 1.08 ether over 2 years
    }

    function testIntegratedPrice() public {
        uint256 minPrice = pricing.minAnnualPrice();
        (uint256 simpleMinSpent, uint256 simpleMinPrice) = pricing.getIntegratedPrice(minPrice, 730 days);
        assertEq(simpleMinSpent, 2 * minPrice);
        assertEq(simpleMinPrice, minPrice);

        (uint256 simpleDecaySpent, uint256 simpleDecayPrice) = pricing.getIntegratedPrice(1 ether, 730 days);
        assertEq(simpleDecaySpent, 1082021280666722556); // 1.08 ether over 2 years
        assertEq(simpleDecayPrice, 0.25e18 - 1); // Cut in half every year, now a quarter of start price

        (uint256 simpleDecaySpent2, uint256 simpleDecayPrice2) = pricing.getIntegratedPrice(1 ether, 209520648);
        assertEq(simpleDecaySpent2, 1428268090226162139); // 1.42 ether over 6.64 years
        assertEq(simpleDecayPrice2, 10000000175998132); // ~0.01 price after 6.64 years

        (uint256 complexDecaySpent, uint256 complexDecayPrice) = pricing.getIntegratedPrice(1 ether, 10 * 365 days);
        assertEq(complexDecaySpent, 1461829528582326522); // 1.42 ether over 6.6 years then 0.03 ether over 3 years
        assertEq(complexDecayPrice, minPrice);
    }
}
