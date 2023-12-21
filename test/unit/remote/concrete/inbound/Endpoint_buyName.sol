// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
//import {ECDSA} from "solady/utils/ECDSA.sol";

contract Inbound_Endpoint_buyName_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function testBuyName() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(users.alicePrimary), minPrice, constants.TEST_NAME()
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000 gwei, uint128(minPrice));
        (uint256 nativeFee, ) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, nativeFee, payable(msg.sender));
        verifyPackets(1, address(remoteEndpoint));
    }
}