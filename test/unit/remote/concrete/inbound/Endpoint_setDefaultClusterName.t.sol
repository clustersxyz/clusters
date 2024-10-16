// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract Inbound_Endpoint_setDefaultClusterName_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function setUp() public virtual override {
        Inbound_Harberger_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
    }

    function testSetDefaultClusterName() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "setDefaultClusterName(bytes32,string)", _addressToBytes32(users.alicePrimary), "zodomo"
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);
        (uint256 nativeFee,) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, payable(msg.sender));
        //verifyPackets(1, address(localEndpoint));
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](2);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        names[1] = _stringToBytes32("zodomo");
        assertBalances(1, minPrice * 2, 0, minPrice * 2, 0);
        assertNameBacking(1, constants.TEST_NAME(), minPrice);
        assertUnverifiedAddresses(1, 1, 0, unverified);
        assertVerifiedAddresses(1, 1, 1, verified);
        assertClusterNames(1, 1, 2, names);
    }
}
