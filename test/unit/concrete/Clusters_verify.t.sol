// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_verify_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.add(_addressToBytes32(users.aliceSecondary));
        clusters.add(_addressToBytes32(users.bobPrimary));
        vm.stopPrank();

        vm.prank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");

        vm.prank(users.bobSecondary);
        clusters.buyName{value: minPrice}(minPrice, "FOOBAR");
    }

    function testVerify() public {
        vm.prank(users.aliceSecondary);
        clusters.verify(1);

        bytes32[] memory empty;
        bytes32[] memory verified = new bytes32[](2);
        verified[0] = _addressToBytes32(users.alicePrimary);
        verified[1] = _addressToBytes32(users.aliceSecondary);
        assertUnverifiedAddresses(1, 1, empty);
        assertVerifiedAddresses(1, 2, verified);
    }

    function testVerifyInCluster() public {
        vm.prank(users.bobPrimary);
        clusters.verify(1);

        bytes32[] memory empty;
        bytes32[] memory verified = new bytes32[](2);
        bytes32[] memory names = new bytes32[](2);
        verified[0] = _addressToBytes32(users.alicePrimary);
        verified[1] = _addressToBytes32(users.bobPrimary);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        names[1] = _stringToBytes32("zodomo");
        assertUnverifiedAddresses(1, 1, empty);
        assertVerifiedAddresses(1, 2, verified);
        assertClusterNames(1, 2, names);

        vm.prank(users.bobSecondary);
        clusters.add(_addressToBytes32(users.bobPrimary));

        vm.prank(users.bobPrimary);
        clusters.verify(3);

        verified = new bytes32[](2);
        verified[0] = _addressToBytes32(users.bobSecondary);
        verified[1] = _addressToBytes32(users.bobPrimary);
        assertUnverifiedAddresses(3, 0, empty);
        assertVerifiedAddresses(3, 2, verified);
        verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        assertVerifiedAddresses(1, 1, verified);
        assertVerifiedAddresses(2, 0, empty);
    }

    function testVerify_Reverts() public {
        vm.startPrank(users.hacker);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.verify(_addressToBytes32(users.alicePrimary), 1);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.verify(1);
        vm.stopPrank();
    }
}
