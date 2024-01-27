// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Clusters_add_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();
        vm.prank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
    }

    function testAdd() public {
        vm.startPrank(users.alicePrimary);
        clusters.add(_addressToBytes32(users.aliceSecondary));
        clusters.add(_addressToBytes32(users.bobPrimary));

        bytes32[] memory unverified = new bytes32[](1);
        bytes32[] memory verified = new bytes32[](1);
        unverified[0] = _addressToBytes32(users.aliceSecondary);
        verified[0] = _addressToBytes32(users.alicePrimary);
        assertUnverifiedAddresses(1, 2, unverified);
        assertVerifiedAddresses(1, 1, verified);
        verified[0] = _addressToBytes32(users.bobPrimary);
        assertVerifiedAddresses(2, 1, verified);
    }

    function testAdd_Reverts() public {
        vm.startPrank(users.hacker);
        vm.expectRevert(IClustersHub.NoCluster.selector);
        clusters.add(_addressToBytes32(users.alicePrimary));
        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.add(_addressToBytes32(users.alicePrimary), _addressToBytes32(users.alicePrimary));
        vm.stopPrank();

        vm.prank(users.alicePrimary);
        vm.expectRevert(IClustersHub.Registered.selector);
        clusters.add(_addressToBytes32(users.alicePrimary));
    }
}
