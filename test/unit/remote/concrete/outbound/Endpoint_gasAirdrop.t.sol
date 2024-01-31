// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Inbound_Harberger_Shared_Test, console2} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

// TODO: Convert Inbound shared test to Outbound when Outbound infra is ready
contract Outbound_Endpoint_gasAirdrop_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testGasAirdrop() public {
        vm.startPrank(users.alicePrimary);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50_000, 0)
            .addExecutorNativeDropOption(uint128(minPrice), _addressToBytes32(users.aliceSecondary));
        uint256 balance = address(users.aliceSecondary).balance;
        (uint256 nativeFee,) = localEndpoint.quote(2, bytes(""), options, false);
        localEndpoint.gasAirdrop{value: nativeFee}(nativeFee, 2, options);
        //verifyPackets(2, address(remoteEndpoint));
        vm.stopPrank();
        assertEq(balance + minPrice, address(users.aliceSecondary).balance, "airdrop balance error");
    }

    function testGasAirdropInMulticall() public {
        vm.startPrank(users.alicePrimary);
        bytes32 caller = _addressToBytes32(users.alicePrimary);
        string memory testName = constants.TEST_NAME();
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50_000, 0)
            .addExecutorNativeDropOption(uint128(minPrice), _addressToBytes32(users.aliceSecondary));
        (uint256 airdropFee,) = localEndpoint.quote(2, bytes(""), options, false);
        uint256 balance = address(users.aliceSecondary).balance;
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("buyName(bytes32,uint256,string)", caller, minPrice, testName);
        data[1] = abi.encodeWithSignature("gasAirdrop(uint256,uint32,bytes)", airdropFee, 2, options);
        vm.stopPrank();

        vm.startPrank(users.signer);
        bytes32 messageHash = localEndpoint.getMulticallHash(data);
        bytes32 digest = localEndpoint.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.prank(users.alicePrimary);
        console2.logBytes(options);
        localEndpoint.multicall{value: airdropFee + minPrice}(data, sig);
        //verifyPackets(2, address(remoteEndpoint));
        assertEq(balance + minPrice, address(users.aliceSecondary).balance, "airdrop balance error");
    }
}
