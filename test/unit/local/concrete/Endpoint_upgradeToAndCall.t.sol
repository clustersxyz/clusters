// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {Endpoint} from "clusters/Endpoint.sol";
import {IEndpoint} from "clusters/interfaces/IEndpoint.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

contract Endpoint_upgradeToAndCall_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testUpgradeToAndCall() public {
        IEndpoint newEndpoint = new Endpoint();
        vm.label(address(newEndpoint), "New Endpoint Implementation");

        vm.prank(users.hacker);
        vm.expectRevert();
        IUUPS(address(endpointProxy)).upgradeToAndCall(address(newEndpoint), bytes(""));

        vm.prank(users.clustersAdmin);
        IUUPS(address(endpointProxy)).upgradeToAndCall(address(newEndpoint), bytes(""));
    }
}
