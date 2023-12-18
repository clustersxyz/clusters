// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "clusters/interfaces/IClusters.sol";

contract Clusters_setDefaultClusterName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
        vm.prank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "FOOBAR");
    }

    function testSetDefaultClusterName() public {
        vm.prank(users.alicePrimary);
        clusters.setDefaultClusterName("zodomo");

        assertEq(clusters.defaultClusterName(1), _stringToBytes32("zodomo"), "defaultClusterName not updated");
    }

    function testSetDefaultClusterName_Reverts() public {
        vm.startPrank(users.hacker);
        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.setDefaultClusterName("");
        vm.expectRevert(IClusters.LongName.selector);
        clusters.setDefaultClusterName("Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.setDefaultClusterName(_addressToBytes32(users.alicePrimary), "zodomo");
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.setDefaultClusterName("zodomo");
        vm.stopPrank();

        vm.prank(users.bobPrimary);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.setDefaultClusterName("zodomo");
    }
}
