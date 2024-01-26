// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test, console2} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract Inbound_Endpoint_refund_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testRefundEx() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(users.alicePrimary), minPrice, constants.TEST_NAME()
        );
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, uint128(minPrice / 2));
        (uint256 nativeFee,) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, payable(msg.sender));
        vm.stopPrank();
        verifyPackets(1, address(localEndpoint));

        assertBalances(1, 0, 0, 0, 0);
        assertEq(minPrice / 2, address(localEndpoint).balance, "endpoint balance error");
        assertEq(
            minPrice / 2, localEndpoint.failedTxRefunds(_addressToBytes32(users.alicePrimary)), "failedTxRefunds error"
        );

        uint256 balance = address(users.alicePrimary).balance;
        vm.prank(users.alicePrimary);
        localEndpoint.refund();
        assertEq(0, address(localEndpoint).balance, "endpoint balance did not decrease");
        assertEq(balance + (minPrice / 2), address(users.alicePrimary).balance, "refund not issued");
    }
}
