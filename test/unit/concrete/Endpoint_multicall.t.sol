// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {ECDSA} from "../../../lib/solady/src/utils/ECDSA.sol";

contract Endpoint_buyName_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testMulticall() public {
        bytes32 caller = _addressToBytes32(users.alicePrimary);
        string memory testName = constants.TEST_NAME();
        bytes[] memory data = new bytes[](5);
        data[0] = abi.encodeWithSignature("buyName(bytes32,uint256,string)", caller, minPrice, testName);
        data[1] = abi.encodeWithSignature("fundName(bytes32,uint256,string)", caller, minPrice, testName);
        data[2] = abi.encodeWithSignature("add(bytes32,bytes32)", caller, _addressToBytes32(users.aliceSecondary));
        data[3] = abi.encodeWithSignature("setWalletName(bytes32,bytes32,string)", caller, caller, "Primary");
        data[4] = abi.encodeWithSignature(
            "setWalletName(bytes32,bytes32,string)", caller, _addressToBytes32(users.aliceSecondary), "Secondary"
        );

        vm.startPrank(users.signer);
        bytes32 messageHash = endpoint.getMulticallHash(caller, data);
        bytes32 digest = endpoint.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.prank(users.alicePrimary);
        endpoint.multicall{value: minPrice * 2}(data, sig);
    }
}
