// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";

contract Inbound_Endpoint_gasAirdrop_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    function testGasAirdrop() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data =
            abi.encodeWithSignature("gasAirdrop(bytes32,uint256)", _addressToBytes32(users.alicePrimary), minPrice);
        (uint256 nativeFee,, bytes memory options) = remoteEndpoint.quote(1, data, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, nativeFee, payable(msg.sender));
        uint256 balance = address(users.alicePrimary).balance;
        vm.stopPrank();

        verifyPackets(1, address(localEndpoint));
        assertEq(balance + minPrice, address(users.alicePrimary).balance, "gas airdrop error");
    }
}
