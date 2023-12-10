// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test} from "./Base.t.sol";

contract GasBenchmarkTest is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
        deployLocalHarberger();
    }

    function testBenchmark() public {
        vm.startPrank(users.signer);
        bytes32 digest = endpoint.getEthSignedMessageHash(_addressToBytes32(users.alicePrimary), "foobar");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig1 = abi.encodePacked(r, s, v);

        digest = endpoint.getEthSignedMessageHash(_addressToBytes32(users.alicePrimary), "zodomo");
        (v, r, s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig2 = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpoint.buyName{value: minPrice}(minPrice, "foobar", sig1);
        endpoint.buyName{value: minPrice}(minPrice, "zodomo", sig2);
        clusters.fundName{value: 0.5 ether}(0.5 ether, "foobar");
        clusters.add(_addressToBytes32(users.aliceSecondary));
        clusters.setDefaultClusterName("zodomo");
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");
        vm.stopPrank();

        vm.prank(users.aliceSecondary);
        clusters.verify(1);

        vm.startPrank(users.alicePrimary);
        bytes[] memory data = new bytes[](5);
        data[0] = abi.encodeWithSignature("fundName(uint256,string)", 0.5 ether, "foobar");
        data[1] = abi.encodeWithSignature("fundName(uint256,string)", 1 ether, "zodomo");
        data[2] = abi.encodeWithSignature("setDefaultClusterName(string)", "foobar");
        data[3] =
            abi.encodeWithSignature("setWalletName(bytes32,string)", _addressToBytes32(users.alicePrimary), "Main");
        data[4] = abi.encodeWithSignature(
            "setWalletName(bytes32,string)", _addressToBytes32(users.aliceSecondary), "Secondary"
        );
        clusters.multicall{value: minPrice + 1.5 ether}(data);
        clusters.remove(_addressToBytes32(users.aliceSecondary));
        vm.stopPrank();

        vm.startPrank(users.bidder);
        clusters.bidName{value: 2 ether}(2 ether, "foobar");
        vm.warp(constants.START_TIME() + 14 days);
        clusters.pokeName("foobar");
        vm.warp(constants.START_TIME() + 31 days);
        clusters.reduceBid("foobar", 1 ether);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, "burned");
        clusters.transferName("burned", 0);
        clusters.acceptBid("foobar");
        clusters.transferName("zodomo", 2);
        vm.stopPrank();
    }
}
