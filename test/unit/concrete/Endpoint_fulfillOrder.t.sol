// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger_Unit_Shared_Test} from "../shared/SharedPricingHarberger.t.sol";
import {ECDSA} from "../../../lib/solady/src/utils/ECDSA.sol";
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
        bytes32 digest =
            endpoint.prepareOrder(0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, address(0), testName);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpoint.fulfillOrder{value: minPrice * 3}(
            0, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, testName, sig, users.signer
        );
        vm.stopPrank();

        vm.startPrank(users.signer);
        digest = endpoint.prepareOrder(
            2, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, users.alicePrimary, "zodomo"
        );
        (v, r, s) = vm.sign(users.signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
        console2.log(
            endpoint.verifyOrder(
                2,
                constants.MARKET_OPEN_TIMESTAMP() + 2 days,
                minPrice * 3,
                users.alicePrimary,
                "zodomo",
                sig,
                users.signer
            )
        );
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpoint.fulfillOrder{value: minPrice * 3}(
            2, constants.MARKET_OPEN_TIMESTAMP() + 2 days, minPrice * 3, "zodomo", sig, users.signer
        );
        vm.stopPrank();
    }
}
