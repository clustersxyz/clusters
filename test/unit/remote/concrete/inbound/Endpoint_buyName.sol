// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract Inbound_Endpoint_buyName_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    function testBuyName() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(users.alicePrimary), minPrice, constants.TEST_NAME()
        );
        bytes memory options;
        MessagingFee memory fee;
        address refundAddress;
        //localEndpoint.lzSend(data, options, fee, refundAddress);
    }
}
