// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test, IEndpoint, IClustersHub} from "./Base.t.sol";

contract GasBenchmarkTest is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(1);
    }

    function testBenchmark() public {
        bytes[] memory buyBatchData = new bytes[](2);
        buyBatchData[0] = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string,bytes)", users.alicePrimary, minPrice, constants.TEST_NAME(), bytes("")
        );
        buyBatchData[1] =
            abi.encodeWithSignature("buyName(bytes32,uint256,string,bytes)", users.alicePrimary, minPrice, "zodomo", bytes(""));

        vm.startPrank(users.signer);
        bytes32 messageHash = endpointProxy.getMulticallHash(buyBatchData);
        bytes32 digest = endpointProxy.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig1 = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpointProxy.multicall{value: 2 * minPrice}(buyBatchData, sig1, bytes(""));
        clusters.fundName{value: 0.5 ether}(0.5 ether, constants.TEST_NAME(), bytes(""));
        clusters.add(_addressToBytes32(users.aliceSecondary), bytes(""));
        clusters.setDefaultClusterName("zodomo", bytes(""));
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary", bytes(""));
        vm.stopPrank();

        vm.prank(users.aliceSecondary);
        clusters.verify(1, bytes(""));

        vm.startPrank(users.alicePrimary);
        bytes[] memory data = new bytes[](5);
        data[0] = abi.encodeWithSignature("fundName(uint256,string,bytes)", 0.5 ether, constants.TEST_NAME(), bytes(""));
        data[1] = abi.encodeWithSignature("fundName(uint256,string,bytes)", 1 ether, "zodomo", bytes(""));
        data[2] = abi.encodeWithSignature("setDefaultClusterName(string,bytes)", constants.TEST_NAME(), bytes(""));
        data[3] =
            abi.encodeWithSignature("setWalletName(bytes32,string,bytes)", _addressToBytes32(users.alicePrimary), "Main", bytes(""));
        data[4] = abi.encodeWithSignature(
            "setWalletName(bytes32,string,bytes)", _addressToBytes32(users.aliceSecondary), "Secondary", bytes("")
        );
        clusters.multicall{value: minPrice + 1.5 ether}(data, bytes(""));
        clusters.remove(_addressToBytes32(users.aliceSecondary), bytes(""));
        vm.stopPrank();

        vm.startPrank(users.bidder);
        clusters.bidName{value: 2 ether}(2 ether, constants.TEST_NAME(), bytes(""));
        vm.warp(constants.START_TIME() + 14 days);
        clusters.pokeName(constants.TEST_NAME(), bytes(""));
        vm.warp(constants.START_TIME() + 31 days);
        clusters.reduceBid(constants.TEST_NAME(), 1 ether);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, "burned", bytes(""));
        clusters.transferName("burned", 0, bytes(""));
        clusters.acceptBid(constants.TEST_NAME());
        clusters.transferName("zodomo", 2, bytes(""));
        vm.stopPrank();
    }
}
