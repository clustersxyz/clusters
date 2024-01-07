// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {PricingHarberger} from "clusters/PricingHarberger.sol";
import {IPricing} from "clusters/interfaces/IPricing.sol";
import {IUUPS} from "clusters/interfaces/IUUPS.sol";

contract Pricing_upgradeToAndCall_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testUpgradeToAndCall() public {
        IPricing newPricing = new PricingHarberger();
        vm.label(address(newPricing), "New Pricing Implementation");

        vm.prank(users.hacker);
        vm.expectRevert();
        IUUPS(address(pricingProxy)).upgradeToAndCall(address(newPricing), bytes(""));

        vm.prank(users.clustersAdmin);
        IUUPS(address(pricingProxy)).upgradeToAndCall(address(newPricing), bytes(""));
    }
}
