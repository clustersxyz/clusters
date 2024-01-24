// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test, Endpoint, EnumerableSet, IEndpoint, IClustersHub} from "./Base.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract TestpadTest is Base_Test {
    using EnumerableSet for EnumerableSet.AddressSet;
    using OptionsBuilder for bytes;

    Endpoint internal localEndpoint;
    Endpoint internal remoteEndpoint;

    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(2);
        localEndpoint = Endpoint(endpointGroup.at(0));
        remoteEndpoint = Endpoint(endpointGroup.at(1));
    }

    function testPad() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(users.alicePrimary), 0.01 ether, "zodomo3"
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(275_000, uint128(0.01 ether));
        (uint256 nativeFee,) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, users.alicePrimary);
        verifyPackets(1, address(localEndpoint));
        vm.stopPrank();
    }
}
