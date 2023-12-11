// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_bidName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
    }

    function testBidName() public {
        vm.startPrank(users.bobPrimary);
        clusters.bidName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        assertEq(ethAmount, minPrice, "bid value error");
        assertEq(createdTimestamp, constants.MARKET_OPEN_TIMESTAMP() + 1 days, "bid timestamp error");
        assertEq(bidder, _addressToBytes32(users.bobPrimary), "bid bidder error");
        assertBalances(minPrice * 3, 0, minPrice * 2, minPrice);
    }

    function testBidNameIncrease() public {
        vm.startPrank(users.bobPrimary);
        clusters.bidName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.bidName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        assertEq(ethAmount, minPrice * 2, "bid value error");
        assertEq(createdTimestamp, constants.MARKET_OPEN_TIMESTAMP() + 1 days, "bid timestamp error");
        assertEq(bidder, _addressToBytes32(users.bobPrimary), "bid bidder error");
        assertBalances(minPrice * 4, 0, minPrice * 2, minPrice * 2);
    }

    function testBidName_Reverts() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.bidName{value: minPrice}(minPrice, "");
        vm.expectRevert(IClusters.LongName.selector);
        clusters.bidName{value: minPrice}(minPrice, "Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClusters.NoBid.selector);
        clusters.bidName{value: 0}(0, "zodomo");
        vm.expectRevert(IClusters.SelfBid.selector);
        clusters.bidName{value: minPrice}(minPrice, testName);

        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.bidName{value: minPrice}(minPrice, "FOOBAR");
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice - 1}(minPrice - 1, "zodomo");

        vm.expectRevert(IClusters.BadInvariant.selector);
        clusters.bidName{value: minPrice}(minPrice + 1, "zodomo");
        clusters.bidName{value: minPrice * 2}(minPrice * 2, "zodomo");
        vm.stopPrank();

        vm.prank(users.bidder);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice}(minPrice, "zodomo");
    }
}
