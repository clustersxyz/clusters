// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {Endpoint} from "clusters/Endpoint.sol";
import {IEndpoint} from "clusters/interfaces/IEndpoint.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Endpoint_upgradeToAndCall_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testUpgradeToAndCall() public {
        IEndpoint newEndpoint = new Endpoint();
        vm.label(address(newEndpoint), "New Endpoint Implementation");

        vm.prank(users.clustersAdmin);
        vm.expectRevert();
        ITransparentUpgradeableProxy(address(endpointProxy)).upgradeToAndCall(address(newEndpoint), bytes(""));

        vm.prank(users.proxyAdmin);
        ITransparentUpgradeableProxy(address(endpointProxy)).upgradeToAndCall(address(newEndpoint), bytes(""));
    }
}
