// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Endpoint_setSignerAddr_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testSetSignerAddr() public {
        address testAddr = constants.TEST_ADDRESS();
        assertEndpointVars(address(clusters), users.signer);

        vm.prank(users.adminEndpoint);
        endpoint.setSignerAddr(testAddr);

        assertEndpointVars(address(clusters), testAddr);
    }

    function testSetSignerAddr_RevertUnauthorized() public {
        address testAddr = constants.TEST_ADDRESS();
        vm.prank(users.hacker);
        vm.expectRevert(IClusters.Unauthorized.selector);
        endpoint.setSignerAddr(testAddr);
    }
}
