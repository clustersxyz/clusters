// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Clusters_remove_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.add(_addressToBytes32(users.aliceSecondary));
        vm.stopPrank();

        vm.prank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");

        vm.prank(users.aliceSecondary);
        clusters.verify(1);
    }

    function testRemove() public {
        vm.prank(users.aliceSecondary);
        clusters.remove(_addressToBytes32(users.alicePrimary));

        bytes32[] memory empty;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.aliceSecondary);
        assertUnverifiedAddresses(1, 0, empty);
        assertVerifiedAddresses(1, 1, verified);
    }

    function testRemoveNamed() public {
        vm.prank(users.alicePrimary);
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");

        vm.prank(users.aliceSecondary);
        clusters.remove(_addressToBytes32(users.alicePrimary));

        bytes32[] memory empty;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.aliceSecondary);
        assertUnverifiedAddresses(1, 0, empty);
        assertVerifiedAddresses(1, 1, verified);
        assertEq(bytes32(""), clusters.reverseLookup(_addressToBytes32(users.alicePrimary)), "name not purged");
    }

    function testRemove_Reverts() public {
        vm.startPrank(users.hacker);
        vm.expectRevert(IClustersHub.NoCluster.selector);
        clusters.remove(_addressToBytes32(users.aliceSecondary));

        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.remove(_addressToBytes32(users.alicePrimary), _addressToBytes32(users.aliceSecondary));
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        clusters.remove(_addressToBytes32(users.aliceSecondary));
        vm.expectRevert(IClustersHub.Invalid.selector);
        clusters.remove(_addressToBytes32(users.alicePrimary));
        vm.stopPrank();
    }
}
