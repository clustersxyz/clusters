// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract Endpoint_ECDSA_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function testECDSAGeneralOrder() public {
        string memory testName = constants.TEST_NAME();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);

        vm.startPrank(users.signer);
        clusters.buyName{value: minPrice}(minPrice, testName);

        bytes32 messageHash =
            endpoint.getOrderHash(0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, bytes32(""), testName);
        bytes32 digest = endpoint.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        bool valid = endpoint.verifyOrder(
            0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, bytes32(""), testName, sig, users.signer
        );
        assertEq(valid, true, "ECDSA verification error");
    }

    function testECDSASpecificOrder() public {
        string memory testName = constants.TEST_NAME();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);

        vm.startPrank(users.signer);
        clusters.buyName{value: minPrice}(minPrice, testName);

        bytes32 messageHash = endpoint.getOrderHash(
            0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, _addressToBytes32(users.alicePrimary), testName
        );
        bytes32 digest = endpoint.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        bool valid = endpoint.verifyOrder(
            0,
            constants.MARKET_OPEN_TIMESTAMP() + 2 days,
            minPrice * 3,
            _addressToBytes32(users.alicePrimary),
            testName,
            sig,
            users.signer
        );
        assertEq(valid, true, "ECDSA verification error");
    }
}
