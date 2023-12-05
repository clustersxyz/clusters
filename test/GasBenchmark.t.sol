// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test} from "./Base.t.sol";

contract GasBenchmarkTest is Test {
    address constant LZENDPOINT = address(uint160(uint256(keccak256(abi.encode("lzEndpoint")))));

    PricingHarberger public pricing;
    Endpoint public endpoint;
    Clusters public clusters;
    uint256 public minPrice;

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(LZENDPOINT);
        clusters = new Clusters(address(pricing), address(endpoint));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function testBenchmark() public {
        bytes[] memory buyBatchData = new bytes[](2);
        buyBatchData[0] = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", users.alicePrimary, minPrice, constants.TEST_NAME()
        );
        buyBatchData[1] =
            abi.encodeWithSignature("buyName(bytes32,uint256,string)", users.alicePrimary, minPrice, "zodomo");

        vm.startPrank(users.signer);
        bytes32 messageHash = endpoint.getMulticallHash(buyBatchData);
        bytes32 digest = endpoint.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig1 = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        endpoint.multicall{value: 2 * minPrice}(buyBatchData, sig1);
        clusters.fundName{value: 0.5 ether}(0.5 ether, constants.TEST_NAME());
        clusters.add(_addressToBytes32(users.aliceSecondary));
        clusters.setDefaultClusterName("zodomo");
        clusters.setWalletName(_addressToBytes32(users.alicePrimary), "Primary");
        vm.stopPrank();

        vm.prank(users.aliceSecondary);
        clusters.verify(1);

        vm.startPrank(users.alicePrimary);
        bytes[] memory data = new bytes[](5);
        data[0] = abi.encodeWithSignature("fundName(uint256,string)", 0.5 ether, constants.TEST_NAME());
        data[1] = abi.encodeWithSignature("fundName(uint256,string)", 1 ether, "zodomo");
        data[2] = abi.encodeWithSignature("setDefaultClusterName(string)", constants.TEST_NAME());
        data[3] =
            abi.encodeWithSignature("setWalletName(bytes32,string)", _addressToBytes32(users.alicePrimary), "Main");
        data[4] = abi.encodeWithSignature(
            "setWalletName(bytes32,string)", _addressToBytes32(users.aliceSecondary), "Secondary"
        );
        clusters.multicall{value: minPrice + 1.5 ether}(data);
        clusters.remove(_addressToBytes32(users.aliceSecondary));
        vm.stopPrank();

        vm.startPrank(users.bidder);
        clusters.bidName{value: 2 ether}(2 ether, constants.TEST_NAME());
        vm.warp(constants.START_TIME() + 14 days);
        clusters.pokeName(constants.TEST_NAME());
        vm.warp(constants.START_TIME() + 31 days);
        clusters.reduceBid(constants.TEST_NAME(), 1 ether);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        clusters.buyName{value: minPrice}(minPrice, "burned");
        clusters.transferName("burned", 0);
        clusters.acceptBid(constants.TEST_NAME());
        clusters.transferName("zodomo", 2);
        vm.stopPrank();
    }
}
