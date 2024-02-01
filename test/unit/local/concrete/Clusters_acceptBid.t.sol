// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Clusters_acceptBid_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        vm.startPrank(users.bidder);
        clusters.bidName{value: minPrice * 2}(minPrice * 2, constants.TEST_NAME());
        vm.stopPrank();

        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 10 days);
    }

    function testAcceptBid() public {
        vm.startPrank(users.alicePrimary);
        clusters.acceptBid(constants.TEST_NAME());
        vm.stopPrank();

        bytes32[] memory empty;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.bidder);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        uint256 protocolAccrual = clusters.protocolAccrual();
        uint256 totalNameBacking = clusters.totalNameBacking();
        assertEq(minPrice * 2, protocolAccrual + totalNameBacking, "protocolAccrual and totalNameBacking incoherence");
        assertBalances(minPrice * 2, protocolAccrual, totalNameBacking, 0);
        assertUnverifiedAddresses(3, 0, empty);
        assertVerifiedAddresses(3, 1, verified);
        assertClusterNames(3, 1, names);
    }

    function testAcceptBid_Reverts() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.hacker);

        vm.expectRevert(IClustersHub.EmptyName.selector);
        clusters.acceptBid("");
        vm.expectRevert(IClustersHub.LongName.selector);
        clusters.acceptBid("Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClustersHub.NoCluster.selector);
        clusters.acceptBid(testName);
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.acceptBid(testName);
        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.acceptBid(_addressToBytes32(users.alicePrimary), testName);

        vm.expectRevert(IClustersHub.NoBid.selector);
        clusters.acceptBid("zodomo");
        vm.stopPrank();

        bytes memory data = abi.encodeWithSignature("buyName(uint256,string)", minPrice, "FOOBAR");
        fickleReceiver.execute(address(clusters), minPrice, data);
        fickleReceiver.toggle();

        vm.prank(users.bidder);
        clusters.bidName{value: minPrice * 3}(minPrice * 3, "FOOBAR");

        data = abi.encodeWithSignature("acceptBid(string)", "FOOBAR");
        vm.expectRevert(IClustersHub.NativeTokenTransferFailed.selector);
        fickleReceiver.execute(address(clusters), 0, data);
    }
}
