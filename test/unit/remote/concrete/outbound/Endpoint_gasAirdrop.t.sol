// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

// TODO: Convert Inbound shared test to Outbound when Outbound infra is ready
contract Outbound_Endpoint_gasAirdrop_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testGasAirdrop() public {
        vm.startPrank(users.alicePrimary);
        bytes memory options = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            uint128(minPrice), _addressToBytes32(users.aliceSecondary)
        );
        (uint256 nativeFee,) = localEndpoint.quote(2, bytes(""), options, false);
        localEndpoint.gasAirdrop{value: nativeFee}(2, options);
        verifyPackets(2, address(remoteEndpoint));
        vm.stopPrank();
    }
}
