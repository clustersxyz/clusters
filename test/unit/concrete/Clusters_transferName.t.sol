// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Clusters_transferName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "FOOBAR");
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
    }

    function testTransferName() public {
        vm.startPrank(users.alicePrimary);
        clusters.transferName("FOOBAR", 2);
        vm.stopPrank();

        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        assertClusterNames(1, 1, names);
        names = new bytes32[](2);
        names[0] = _stringToBytes32("zodomo");
        names[1] = _stringToBytes32("FOOBAR");
        assertClusterNames(2, 2, names);
    }

    function testTransferNameZeroCluster() public {
        vm.startPrank(users.alicePrimary);
        clusters.transferName("FOOBAR", 0);
        clusters.bidName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();

        vm.prank(users.bobPrimary);
        clusters.transferName("zodomo", 0);

        bytes32[] memory empty;
        assertClusterNames(0, 0, empty);
        assertClusterNames(1, 1, empty);
        assertClusterNames(2, 0, empty);
        assertBalances(minPrice * 4, minPrice * 2, minPrice, minPrice);
    }

    function testTransferNameAll() public {
        vm.startPrank(users.alicePrimary);
        clusters.transferName("FOOBAR", 2);
        clusters.transferName(constants.TEST_NAME(), 2);
        vm.stopPrank();

        bytes32[] memory empty;
        assertVerifiedAddresses(1, 0, empty);
        assertClusterNames(1, 0, empty);
        bytes32[] memory names = new bytes32[](3);
        names[0] = _stringToBytes32("zodomo");
        names[1] = _stringToBytes32("FOOBAR");
        names[2] = _stringToBytes32(constants.TEST_NAME());
        assertClusterNames(2, 3, names);
    }

    function testTransferName_Reverts() public {
        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.EmptyName.selector);
        clusters.transferName("", 2);
        vm.expectRevert(IClusters.LongName.selector);
        clusters.transferName("Privacy is necessary for an open society in the electronic age.", 2);

        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.transferName("zodomo", 1);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.transferName(_addressToBytes32(users.bobPrimary), "FOOBAR", 0);

        vm.expectRevert(IClusters.Invalid.selector);
        clusters.transferName("FOOBAR", 3);
        vm.stopPrank();

        vm.prank(users.hacker);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.transferName(_addressToBytes32(users.hacker), "FOOBAR", 0);
    }
}
