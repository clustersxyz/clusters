// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "clusters/interfaces/IClusters.sol";

contract Clusters_refundBid_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        bytes memory data = abi.encodeWithSignature("bidName(uint256,string)", minPrice * 2, constants.TEST_NAME());
        fickleReceiver.execute(address(clusters), minPrice * 2, data);
        data = abi.encodeWithSignature("bidName(uint256,string)", minPrice * 2, "zodomo");
        fickleReceiver.execute(address(clusters), minPrice * 2, data);
    }

    function testRefundBidTransferBurn() public {
        vm.startPrank(users.alicePrimary);
        clusters.transferName(constants.TEST_NAME(), 0);
        vm.stopPrank();
        assertEq(minPrice * 2, clusters.bidRefunds(_addressToBytes32(address(fickleReceiver))), "bidRefunds incorrect");
        assertBalances(minPrice * 6, minPrice, minPrice, minPrice * 4);

        uint256 balance = address(fickleReceiver).balance;
        bytes memory data = abi.encodeWithSignature("refundBid()");
        fickleReceiver.execute(address(clusters), 0, data);
        assertEq(address(fickleReceiver).balance, balance + (minPrice * 2), "refund didn't process");
        assertEq(0, clusters.bidRefunds(_addressToBytes32(address(fickleReceiver))), "bidRefunds didn't purge");
        assertBalances(minPrice * 4, minPrice, minPrice, minPrice * 2);
    }

    function testRefundBidOutbid() public {
        fickleReceiver.toggle();

        vm.startPrank(users.bidder);
        clusters.bidName{value: minPrice * 4}(minPrice * 4, "zodomo");
        vm.stopPrank();
        assertEq(minPrice * 2, clusters.bidRefunds(_addressToBytes32(address(fickleReceiver))), "bidRefunds incorrect");
        assertBalances(minPrice * 10, 0, minPrice * 2, minPrice * 8);

        fickleReceiver.toggle();
        uint256 balance = address(fickleReceiver).balance;
        bytes memory data = abi.encodeWithSignature("refundBid()");
        fickleReceiver.execute(address(clusters), 0, data);
        assertEq(address(fickleReceiver).balance, balance + (minPrice * 2), "refund didn't process");
        assertEq(0, clusters.bidRefunds(_addressToBytes32(address(fickleReceiver))), "bidRefunds didn't purge");
        assertBalances(minPrice * 8, 0, minPrice * 2, minPrice * 6);
    }

    function testRefundBid_Reverts() public {
        fickleReceiver.toggle();
        vm.startPrank(users.alicePrimary);
        clusters.transferName(constants.TEST_NAME(), 0);
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.refundBid();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.refundBid(_addressToBytes32(address(fickleReceiver)));
        vm.stopPrank();

        bytes memory data = abi.encodeWithSignature("refundBid()");
        vm.expectRevert(IClusters.NativeTokenTransferFailed.selector);
        fickleReceiver.execute(address(clusters), 0, data);
    }
}
