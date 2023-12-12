// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {ECDSA} from "../../../lib/solady/src/utils/ECDSA.sol";

contract Endpoint_ECDSA_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testECDSA() public {
        string memory testName = constants.TEST_NAME();
        bytes32 alicePrimary = _addressToBytes32(users.alicePrimary);

        vm.startPrank(users.signer);
        bytes32 digest = endpoint.getEthSignedMessageHash(alicePrimary, testName);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        bool valid = endpoint.verify(alicePrimary, testName, sig);
        assertEq(valid, true, "ECDSA verification error");
    }
}
