// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "clusters/interfaces/IClusters.sol";

contract Clusters_multicall_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
    }

    function testMulticall_Reverts() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("verify(uint256)", 1);
        vm.prank(users.alicePrimary);
        vm.expectRevert(IClusters.MulticallFailed.selector);
        clusters.multicall(data);
    }
}
