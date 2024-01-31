// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Endpoint_setSignerAddr_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testSetSignerAddr() public {
        address testAddr = constants.TEST_ADDRESS();
        assertEndpointVars(address(clusters), users.signer);

        vm.prank(users.clustersAdmin);
        endpointProxy.setSignerAddr(testAddr);

        assertEndpointVars(address(clusters), testAddr);
    }

    function testSetSignerAddr_RevertUnauthorized() public {
        address testAddr = constants.TEST_ADDRESS();
        vm.prank(users.hacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", users.hacker));
        endpointProxy.setSignerAddr(testAddr);
    }
}
