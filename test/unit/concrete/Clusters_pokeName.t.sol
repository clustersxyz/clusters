// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_pokeName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.bidName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 31 days);
    }

    function testPokeName() public {
        clusters.pokeName(constants.TEST_NAME());
        clusters.pokeName("zodomo");

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        uint256 protocolAccrual = clusters.protocolAccrual();
        uint256 totalNameBacking = clusters.totalNameBacking();
        assertEq(protocolAccrual > 0, true, "protocolAccrual didn't increase");
        assertEq(totalNameBacking < minPrice * 2, true, "totalNameBacking didn't decrease");
        assertEq(minPrice * 2, protocolAccrual + totalNameBacking, "protocolAccrual and totalNameBacking incohesive");
        assertBalances(minPrice * 3, protocolAccrual, totalNameBacking, minPrice);
        assertClusterNames(1, 2, names);
    }

    function testPokeNameExhaustBacking() public {
        clusters.pokeName(constants.TEST_NAME());
        clusters.pokeName("zodomo");
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + (10 * 365 days));
        clusters.pokeName(constants.TEST_NAME());
        clusters.pokeName("zodomo");

        bytes32[] memory empty;
        bytes32[] memory addrs = new bytes32[](1);
        addrs[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = clusters.getClusterNamesBytes32(2);
        assertBalances(minPrice * 3, minPrice * 2, minPrice, 0);
        assertVerifiedAddresses(1, 1, addrs);
        addrs = clusters.getVerifiedAddresses(2);
        assertVerifiedAddresses(2, 1, addrs);
        assertClusterNames(1, 0, empty);
        assertClusterNames(2, 1, names);
    }

    function testPokeName_Reverts() public {
        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.pokeName("");
        vm.expectRevert(IClusters.LongName.selector);
        clusters.pokeName("Privacy is necessary for an open society in the electronic age.");

        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.pokeName("FOOBAR");
        vm.stopPrank();
    }
}
