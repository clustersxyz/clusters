// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {Lambert} from "../src/Lambert.sol";
import {ClusterData} from "../src/libraries/ClusterData.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;
    Lambert public lambert;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        require(smallBytes.length <= 32, "name too long");
        return bytes32(smallBytes);
    }

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
        lambert = new Lambert();
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
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
        uint256 newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 0);
        assertEq(newPrice, 1 ether);

        newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 15 days);
        assertEq(newPrice, 1.25 ether);

        newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 30 days);
        assertEq(newPrice, 2 ether);
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

    function createCluster() public {
        clusters.create();
    }

    function buyName() public {
        clusters.buyName{ value: 0.1 ether }("Test Name", 1);
    }

    function testBuyName() public {
        createCluster();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testTransferName() public {
        createCluster();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.prank(address(1));
        createCluster();
        clusters.transferName("Test Name", 2);
        require(clusters.addressLookup(address(1)) == 2, "address(1) not assigned to cluster");
        require(clusters.nameLookup(name) == 2, "name not assigned to proper cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testPokeName() public {
        createCluster();
        buyName();
        vm.prank(address(1));
        clusters.pokeName("Test Name");
        bytes32 name = _toBytes32("Test Name");
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testBidName() public {
        createCluster();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(address(1), 1 ether);
        vm.startPrank(address(1));
        clusters.create();
        clusters.bidName{ value: 0.2 ether }("Test Name");
        vm.stopPrank();
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.3 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.2 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == address(1), "bid bidder incorrect");
    }

    function testReduceBid() public {
        createCluster();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(address(1), 1 ether);
        vm.startPrank(address(1));
        clusters.create();
        clusters.bidName{ value: 0.2 ether }("Test Name");
        uint256 balance = address(1).balance;
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid("Test Name", 0.05 ether);
        vm.stopPrank();
        require(address(1).balance == balance + 0.05 ether, "refund error");
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.25 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.15 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == address(1), "bid bidder incorrect");
    }

    function testRevokeBid() public {
        createCluster();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(address(1), 1 ether);
        vm.startPrank(address(1));
        clusters.create();
        clusters.bidName{ value: 0.2 ether }("Test Name");
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid("Test Name", 0.2 ether);
        vm.stopPrank();
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }
}
