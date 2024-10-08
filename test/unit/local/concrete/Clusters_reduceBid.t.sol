// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Clusters_reduceBid_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.bidName{value: minPrice * 2}(minPrice * 2, constants.TEST_NAME());
        vm.stopPrank();

        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 32 days);
    }

    function testReduceBid() public {
        vm.startPrank(users.bobPrimary);
        clusters.reduceBid(constants.TEST_NAME(), minPrice);
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        uint256 protocolAccrual = clusters.protocolAccrual();
        uint256 totalNameBacking = clusters.totalNameBacking();
        assertEq(minPrice, protocolAccrual + totalNameBacking, "protocolAccrual and totalNameBacking incoherence");
        assertEq(ethAmount, minPrice, "bid value error");
        assertEq(createdTimestamp, constants.MARKET_OPEN_TIMESTAMP() + 1 days, "bid timestamp error");
        assertEq(bidder, _addressToBytes32(users.bobPrimary), "bid bidder error");
        assertBalances(minPrice * 2, protocolAccrual, totalNameBacking, minPrice);
    }

    function testReduceBidAll() public {
        vm.startPrank(users.bobPrimary);
        clusters.reduceBid(constants.TEST_NAME(), minPrice * 2);
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        uint256 protocolAccrual = clusters.protocolAccrual();
        uint256 totalNameBacking = clusters.totalNameBacking();
        assertEq(minPrice, protocolAccrual + totalNameBacking, "protocolAccrual and totalNameBacking incoherence");
        assertEq(ethAmount, 0, "bid value not reset");
        assertEq(createdTimestamp, 0, "bid timestamp not reset");
        assertEq(bidder, bytes32(""), "bid bidder not reset");
        assertBalances(minPrice, protocolAccrual, totalNameBacking, 0);
    }

    function testReduceBidOverage() public {
        vm.startPrank(users.bobPrimary);
        clusters.reduceBid(constants.TEST_NAME(), minPrice * 3);
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        uint256 protocolAccrual = clusters.protocolAccrual();
        uint256 totalNameBacking = clusters.totalNameBacking();
        assertEq(minPrice, protocolAccrual + totalNameBacking, "protocolAccrual and totalNameBacking incoherence");
        assertEq(ethAmount, 0, "bid value not reset");
        assertEq(createdTimestamp, 0, "bid timestamp not reset");
        assertEq(bidder, bytes32(""), "bid bidder not reset");
        assertBalances(minPrice, protocolAccrual, totalNameBacking, 0);
    }

    function testReduceBidAfterExpiry() public {
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + (10 * 365 days));
        vm.startPrank(users.bobPrimary);
        clusters.reduceBid(constants.TEST_NAME(), minPrice * 3);
        vm.stopPrank();

        (uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) =
            clusters.bids(_stringToBytes32(constants.TEST_NAME()));
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        assertEq(ethAmount, 0, "bid value not reset");
        assertEq(createdTimestamp, 0, "bid timestamp not reset");
        assertEq(bidder, bytes32(""), "bid bidder not reset");
        assertBalances(minPrice * 3, minPrice, minPrice * 2, 0);
        assertClusterNames(2, 1, names);
    }

    function testReduceBid_Reverts() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.bobPrimary);

        vm.expectRevert(IClustersHub.EmptyName.selector);
        clusters.reduceBid("", minPrice);
        vm.expectRevert(IClustersHub.LongName.selector);
        clusters.reduceBid("Privacy is necessary for an open society in the electronic age.", minPrice);

        vm.expectRevert(IClustersHub.NoBid.selector);
        clusters.reduceBid("zodomo", minPrice);
        vm.expectRevert(IClustersHub.Insufficient.selector);
        clusters.reduceBid(testName, minPrice + 1);

        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 2 days);
        vm.expectRevert(IClustersHub.Timelock.selector);
        clusters.reduceBid(testName, minPrice);
        vm.stopPrank();

        vm.prank(users.hacker);
        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.reduceBid(testName, minPrice);

        bytes memory data = abi.encodeWithSignature("bidName(uint256,string)", minPrice * 3, testName);
        fickleReceiver.execute(address(clusters), minPrice * 3, data);
        fickleReceiver.toggle();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 35 days);
        data = abi.encodeWithSignature("reduceBid(string,uint256)", testName, minPrice);
        vm.expectRevert(IClustersHub.NativeTokenTransferFailed.selector);
        fickleReceiver.execute(address(clusters), 0, data);
        vm.stopPrank();
    }
}
