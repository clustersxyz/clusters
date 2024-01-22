// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Outbound_Harberger_Shared_Test, console2, MessagingFee} from "../../shared/SharedOutboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract Outbound_Endpoint_gasAirdrop_Unit_Concrete_Test is Outbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testBuyName__() public {
        vm.startPrank(users.alicePrimary);
        // Prepare relay payload information
        bytes memory relayData = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(users.alicePrimary), minPrice, constants.TEST_NAME()
        );
        bytes memory relayOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000 gwei, uint128(0));
        (uint256 relayNativeFee,) = localEndpoint.quote(2, relayData, relayOptions, false);
        // Prepare initiator payload information
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string,bytes)", _addressToBytes32(users.alicePrimary), minPrice, constants.TEST_NAME(), relayOptions
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000 gwei, uint128(minPrice + relayNativeFee));
        (uint256 nativeFee,) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, payable(msg.sender));
        verifyPackets(1, address(localEndpoint));
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        assertBalances(1, minPrice, 0, minPrice, 0);
        assertNameBacking(1, constants.TEST_NAME(), minPrice);
        assertUnverifiedAddresses(1, 1, 0, unverified);
        assertVerifiedAddresses(1, 1, 1, verified);
        assertClusterNames(1, 1, 1, names);
    }
}