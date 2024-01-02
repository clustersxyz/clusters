// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {console2} from "forge-std/Test.sol";

contract Endpoint_fulfillOrder_Unit_Concrete_Test is PricingHarberger_Unit_Shared_Test {
    function setUp() public virtual override {
        PricingHarberger_Unit_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        string memory testName = constants.TEST_NAME();

        vm.startPrank(users.signer);
        clusters.buyName{value: minPrice}(minPrice, testName);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
    }

    function testFulfillOrder() public {
        vm.startPrank(users.signer);
        string memory testName = constants.TEST_NAME();
        bytes32 messageHash = endpointProxy.getOrderHash(
            0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, bytes32(""), testName
        );
        bytes32 digest = endpointProxy.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpointProxy.fulfillOrder{value: minPrice * 3}(
            minPrice * 3, 0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, bytes32(""), testName, sig, users.signer
        );
        vm.stopPrank();

        vm.startPrank(users.signer);
        messageHash = endpointProxy.getOrderHash(
            2, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, _addressToBytes32(users.alicePrimary), "zodomo"
        );
        digest = endpointProxy.getEthSignedMessageHash(messageHash);
        (v, r, s) = vm.sign(users.signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
        console2.log(
            endpointProxy.verifyOrder(
                2,
                constants.MARKET_OPEN_TIMESTAMP() + 2 days,
                minPrice * 3,
                _addressToBytes32(users.alicePrimary),
                "zodomo",
                sig,
                users.signer
            )
        );
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpointProxy.fulfillOrder{value: minPrice * 3}(
            minPrice * 3,
            2,
            constants.MARKET_OPEN_TIMESTAMP() + 2 days,
            _addressToBytes32(users.alicePrimary),
            "zodomo",
            sig,
            users.signer
        );
        vm.stopPrank();
    }
}
