// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Inbound_Harberger_Shared_Test} from "../../shared/SharedInboundHarbergerTest.t.sol";

contract Inbound_Endpoint_add_Unit_Concrete_Test is Inbound_Harberger_Shared_Test {
    function setUp() public virtual override {
        Inbound_Harberger_Shared_Test.setUp();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, constants.TEST_NAME());
        vm.stopPrank();
    }

    function testAdd() public {
        vm.startPrank(users.alicePrimary);
        bytes memory data = abi.encodeWithSignature(
            "add(bytes32,bytes32)", _addressToBytes32(users.alicePrimary), _addressToBytes32(users.aliceSecondary)
        );
        (uint256 nativeFee,, bytes memory options) = remoteEndpoint.quote(1, data, false);
        remoteEndpoint.lzSend{value: nativeFee}(data, options, nativeFee, payable(msg.sender));
        verifyPackets(1, address(localEndpoint));
        vm.stopPrank();

        bytes32[] memory unverified = new bytes32[](1);
        unverified[0] = _addressToBytes32(users.aliceSecondary);
        bytes32[] memory verified = new bytes32[](1);
        verified[0] = _addressToBytes32(users.alicePrimary);
        bytes32[] memory names = new bytes32[](1);
        names[0] = _stringToBytes32(constants.TEST_NAME());
        assertBalances(1, minPrice, 0, minPrice, 0);
        assertNameBacking(1, constants.TEST_NAME(), minPrice);
        assertUnverifiedAddresses(1, 1, 1, unverified);
        assertVerifiedAddresses(1, 1, 1, verified);
        assertClusterNames(1, 1, 1, names);
    }
}
