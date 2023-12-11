// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_fundName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();
    }

    function testFundName() public {
        vm.startPrank(users.alicePrimary);
        clusters.fundName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        assertNameBacking(constants.TEST_NAME(), minPrice * 2);
    }

    function testFundNameOther() public {
        vm.startPrank(users.bobPrimary);
        clusters.fundName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();

        assertNameBacking(constants.TEST_NAME(), minPrice * 2);
    }

    function testFundName_Reverts() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.fundName{value: minPrice}(minPrice, "");
        vm.expectRevert(IClusters.LongName.selector);
        clusters.fundName{value: minPrice}(minPrice, "Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.fundName{value: minPrice}(minPrice, "zodomo");
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.fundName{value: minPrice}(_addressToBytes32(users.bobPrimary), minPrice, "zodomo");

        vm.expectRevert(IClusters.BadInvariant.selector);
        clusters.fundName{value: minPrice}(minPrice + 1, testName);
        vm.stopPrank();
    }
}
