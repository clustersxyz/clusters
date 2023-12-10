// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {IClusters} from "../../../src/interfaces/IClusters.sol";

contract Endpoint_buyName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testBuyName() public {
        string memory testName = constants.TEST_NAME();
        vm.startPrank(users.signer);
        bytes32 digest = endpoint.getEthSignedMessageHash(_addressToBytes32(users.alicePrimary), testName);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.buyName{value: minPrice}(minPrice, testName);
        endpoint.buyName{value: minPrice}(minPrice, testName, sig);
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(testName);
        assertBalances(minPrice, 0, minPrice, 0);
        assertUnverifiedAddresses(1, 0, unverified);
        assertVerifiedAddresses(1, 1, verified);
        assertClusterNames(1, 1, names);
    }
}
