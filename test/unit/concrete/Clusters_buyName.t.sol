// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_buyName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testBuyName() public {
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        assertBalances(minPrice, 0, minPrice, 0);
        assertUnverifiedAddresses(1, 0, unverified);
        assertVerifiedAddresses(1, 1, verified);
        assertClusterNames(1, 1, names);
    }

    function testBuyNameExtra() public {
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        names[0] = _stringToBytes32("zodomo");
        assertBalances(minPrice * 2, 0, minPrice * 2, 0);
        assertUnverifiedAddresses(1, 0, unverified);
        assertVerifiedAddresses(1, 1, verified);
        assertClusterNames(1, 2, names);
    }

    function testBuyName_Reverts() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.buyName{value: minPrice}(minPrice, testName);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.buyName{value: minPrice}(_addressToBytes32(users.bobPrimary), minPrice, testName);

        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);

        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.buyName{value: minPrice}(minPrice, "");
        vm.expectRevert(IClusters.LongName.selector);
        clusters.buyName{value: minPrice}(minPrice, "Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.buyName{value: minPrice - 1}(minPrice - 1, testName);
        vm.expectRevert(IClusters.BadInvariant.selector);
        clusters.buyName{value: minPrice}(minPrice + 1, testName);

        clusters.buyName{value: minPrice}(minPrice, testName);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.buyName{value: minPrice}(minPrice, testName);
        vm.stopPrank();
    }
}
