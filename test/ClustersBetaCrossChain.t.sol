// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Base.t.sol";

contract ClustersHubBetaCrossChainTest is Base_Test {
    using OptionsBuilder for bytes;

    event Bid(bytes32 from, uint256 amount, bytes32 name);
    event Bid(bytes32 from, uint256 amount, bytes32 name, bytes32 referralAddress);

    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function testCrosschain() public {
        vm.startPrank(users.alicePrimary);
        clustersProxy.placeBid{value: 0.1 ether}("foobar");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        bytes32[] memory names = new bytes32[](2);
        names[0] = "foobar2";
        names[1] = "foobar3";
        clustersProxy.placeBids{value: 0.2 ether}(amounts, names);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        bytes memory message = abi.encodeWithSignature("placeBid(bytes32)", bytes32("foobarCrosschain"));
        bytes32 from = bytes32(uint256(uint160(address(users.alicePrimary))));
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        vm.expectEmit(address(clustersProxy));
        emit ClustersHubBeta.Bid(from, 0.1 ether, bytes32("foobarCrosschain"));

        initiatorProxy.lzSend{value: nativeFee}(message, options);
        vm.stopPrank();
    }

    function testRemotePlaceBid() public {
        vm.startPrank(users.alicePrimary);
        bytes memory message = abi.encodeWithSignature("placeBid(bytes32)", _stringToBytes32("foobar"));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        vm.expectEmit(address(clustersProxy));
        emit Bid(_addressToBytes32(users.alicePrimary), 0.1 ether, _stringToBytes32("foobar"));

        initiatorProxy.lzSend{value: nativeFee}(message, options);
        vm.stopPrank();
    }

    function testRemotePlaceBidWithReferral() public {
        vm.startPrank(users.alicePrimary);
        bytes memory message = abi.encodeWithSignature(
            "placeBid(bytes32,bytes32)", _stringToBytes32("foobar"), _addressToBytes32(users.bobPrimary)
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        vm.expectEmit(address(clustersProxy));
        emit Bid(
            _addressToBytes32(users.alicePrimary),
            0.1 ether,
            _stringToBytes32("foobar"),
            _addressToBytes32(users.bobPrimary)
        );

        initiatorProxy.lzSend{value: nativeFee}(message, options);
        vm.stopPrank();
    }

    function testRemotePlaceBids() public {
        vm.startPrank(users.alicePrimary);
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        bytes32[] memory names = new bytes32[](4);
        names[0] = _stringToBytes32("foobar");
        names[1] = _stringToBytes32("ryeshrimp");
        names[2] = _stringToBytes32("munam");
        names[3] = _stringToBytes32("zodomo");

        bytes memory message = abi.encodeWithSignature("placeBids(uint256[],bytes32[])", amounts, names);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(399_000, 0.4 ether);
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(_addressToBytes32(users.alicePrimary), amounts[i], names[i]);
        }

        initiatorProxy.lzSend{value: nativeFee}(message, options);
        vm.stopPrank();
    }

    function testRemotePlaceBidsWithReferral() public {
        vm.startPrank(users.alicePrimary);
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        bytes32[] memory names = new bytes32[](4);
        names[0] = _stringToBytes32("foobar");
        names[1] = _stringToBytes32("ryeshrimp");
        names[2] = _stringToBytes32("munam");
        names[3] = _stringToBytes32("zodomo");

        bytes memory message = abi.encodeWithSignature(
            "placeBids(uint256[],bytes32[],bytes32)", amounts, names, _addressToBytes32(users.bobPrimary)
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(399_000, 0.4 ether);
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(_addressToBytes32(users.alicePrimary), amounts[i], names[i], _addressToBytes32(users.bobPrimary));
        }

        initiatorProxy.lzSend{value: nativeFee}(message, options);
        vm.stopPrank();
    }
}
