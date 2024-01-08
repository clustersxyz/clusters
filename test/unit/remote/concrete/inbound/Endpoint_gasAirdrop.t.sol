// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract Inbound_Endpoint_gasAirdrop_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testGasAirdrop() public {
        vm.startPrank(users.alicePrimary);
        bytes memory options = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            uint128(minPrice), _addressToBytes32(users.aliceSecondary)
        );
        uint256 balance = address(users.aliceSecondary).balance;
        (uint256 nativeFee,) = remoteEndpoint.quote(1, bytes(""), options, false);
        remoteEndpoint.gasAirdrop{value: nativeFee}(nativeFee, 1, options);
        verifyPackets(1, address(localEndpoint));
        vm.stopPrank();
        assertEq(balance + minPrice, address(users.aliceSecondary).balance, "airdrop balance error");
    }
}
