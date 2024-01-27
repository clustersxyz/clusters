// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

contract Endpoint_setClustersAddr_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testSetClustersAddr() public {
        address testAddr = constants.TEST_ADDRESS();
        assertEndpointVars(address(clusters), users.signer);

        vm.prank(users.clustersAdmin);
        endpointProxy.setClustersAddr(testAddr);

        assertEndpointVars(testAddr, users.signer);
    }

    function testSetClustersAddr_RevertUnauthorized() public {
        address testAddr = constants.TEST_ADDRESS();
        vm.prank(users.hacker);
        vm.expectRevert("Ownable: caller is not the owner");
        endpointProxy.setClustersAddr(testAddr);
    }
}
