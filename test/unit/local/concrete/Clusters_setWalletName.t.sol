// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Clusters_setWalletName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();
    }

    function testSetWalletName() public {
        vm.prank(users.alicePrimary);
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");

        assertWalletName(1, _addressToBytes32(users.alicePrimary), "Primary");
    }

    function testSetWalletNameErase() public {
        vm.startPrank(users.alicePrimary);
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "");
        vm.stopPrank();

        assertEq(bytes32(""), clusters.forwardLookup(1, _stringToBytes32("Primary")), "forwardLookup not purged");
        assertEq(bytes32(""), clusters.reverseLookup(_addressToBytes32(users.alicePrimary)), "reverseLookup not purged");
    }

    function testSetWalletName_Reverts() public {
        vm.startPrank(users.hacker);
        vm.expectRevert(IClustersHub.NoCluster.selector);
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClustersHub.LongName.selector);
        clusters.setWalletName(
            _addressToBytes32(users.alicePrimary), "Privacy is necessary for an open society in the electronic age."
        );

        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.setWalletName(_addressToBytes32(users.bobPrimary), "Bob");
        vm.expectRevert(IClustersHub.Unauthorized.selector);
        clusters.setWalletName(_addressToBytes32(users.bobPrimary), _addressToBytes32(users.alicePrimary), "Secondary");
    }
}
