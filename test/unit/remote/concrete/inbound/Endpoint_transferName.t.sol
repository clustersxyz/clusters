// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract Inbound_Endpoint_transferName_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    using OptionsBuilder for bytes;

    function setUp() public virtual override {
        Inbound_Harberger_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        clusters.buyName{value: minPrice}(minPrice, "FOOBAR");
        vm.stopPrank();

        vm.startPrank(users.bobPrimary);
        clusters.buyName{value: minPrice}(minPrice, "zodomo");
        vm.stopPrank();
    }

    function testTransferName() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "transferName(bytes32,string,uint256)", _addressToBytes32(users.alicePrimary), "FOOBAR", 2
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, 0);
        (uint256 nativeFee,) = remoteEndpoint.quote(1, data, options, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, payable(msg.sender));
        //verifyPackets(1, address(localEndpoint));
        vm.stopPrank();

        bytes32[] memory unverified;
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.bobPrimary);
        bytes32[] memory names = new bytes32[](2);
        names[0] = _stringToBytes32("zodomo");
        names[1] = _stringToBytes32("FOOBAR");
        assertBalances(1, minPrice * 3, 0, minPrice * 3, 0);
        assertNameBacking(1, "FOOBAR", minPrice);
        assertUnverifiedAddresses(1, 2, 0, unverified);
        assertVerifiedAddresses(1, 2, 1, verified);
        assertClusterNames(1, 2, 2, names);
    }
}
