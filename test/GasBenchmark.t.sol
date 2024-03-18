// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Base.t.sol";

contract GasBenchmarkTest is Base_Test {
    using OptionsBuilder for bytes;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Bid(bytes32 from, uint256 amount, bytes32 name);
    event Bid(bytes32 from, uint256 amount, bytes32 name, bytes32 referralAddress);

    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment();
    }

    function testBenchmark() public {
        //// Full contract testing
        bytes[] memory buyBatchData = new bytes[](2);
        buyBatchData[0] = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", users.alicePrimary, minPrice, constants.TEST_NAME()
        );
        buyBatchData[1] =
            abi.encodeWithSignature("buyName(bytes32,uint256,string)", users.alicePrimary, minPrice, "zodomo");

        vm.startPrank(users.signer);
        bytes32 messageHash = endpointProxy.getMulticallHash(buyBatchData);
        bytes32 digest = endpointProxy.getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivKey, digest);
        bytes memory sig1 = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(users.alicePrimary);
        IEndpoint(endpointGroup.at(0)).multicall{value: 2 * minPrice}(buyBatchData, sig1);
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

        //// Beta contract testing
        bytes memory message;
        bytes memory options;
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256 nativeFee;
        uint256[] memory amounts;
        bytes32[] memory names;
        vm.startPrank(users.alicePrimary);

        /// Local
        // placeBid
        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("foobarLocal"));
        clustersProxy.placeBid{value: 0.1 ether}(_stringToBytes32("foobarLocal"));

        // placeBid with referral
        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("zodomoLocal"), _addressToBytes32(users.bobPrimary));
        clustersProxy.placeBid{value: 0.1 ether}(_stringToBytes32("zodomoLocal"), _addressToBytes32(users.bobPrimary));

        // placeBids
        amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarLocalBatch");
        names[1] = _stringToBytes32("ryeshrimpLocalBatch");
        names[2] = _stringToBytes32("munamLocalBatch");
        names[3] = _stringToBytes32("zodomoLocalBatch");

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i]);
        }
        clustersProxy.placeBids{value: 0.4 ether}(amounts, names);

        // placeBids with referral
        amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarLocalRefer");
        names[1] = _stringToBytes32("ryeshrimpLocalRefer");
        names[2] = _stringToBytes32("munamLocalRefer");
        names[3] = _stringToBytes32("zodomoLocalRefer");

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i], _addressToBytes32(users.bobPrimary));
        }
        clustersProxy.placeBids{value: 0.4 ether}(amounts, names, _addressToBytes32(users.bobPrimary));

        /// Remote
        // placeBid
        message = abi.encodeWithSignature("placeBid(bytes32)", _stringToBytes32("foobarRemote"));
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("foobarRemote"));
        initiatorProxy.lzSend{value: nativeFee}(message, options);

        // placeBid with referral
        message = abi.encodeWithSignature("placeBid(bytes32,bytes32)", _stringToBytes32("zodomoRemote"), _addressToBytes32(users.bobPrimary));
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("zodomoRemote"), _addressToBytes32(users.bobPrimary));
        initiatorProxy.lzSend{value: nativeFee}(message, options);

        // placeBids
        amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarRemoteBatch");
        names[1] = _stringToBytes32("ryeshrimpRemoteBatch");
        names[2] = _stringToBytes32("munamRemoteBatch");
        names[3] = _stringToBytes32("zodomoRemoteBatch");

        message = abi.encodeWithSignature("placeBids(uint256[],bytes32[])", amounts, names);
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(399_000, 0.4 ether);
        nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i]);
        }
        initiatorProxy.lzSend{value: nativeFee}(message, options);

        // placeBids with referral
        amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarRemoteRefer");
        names[1] = _stringToBytes32("ryeshrimpRemoteRefer");
        names[2] = _stringToBytes32("munamRemoteRefer");
        names[3] = _stringToBytes32("zodomoRemoteRefer");

        message = abi.encodeWithSignature("placeBids(uint256[],bytes32[],bytes32)", amounts, names, _addressToBytes32(users.bobPrimary));
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(399_000, 0.4 ether);
        nativeFee = initiatorProxy.quote(abi.encode(from, message), options);

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i], _addressToBytes32(users.bobPrimary));
        }
        initiatorProxy.lzSend{value: nativeFee}(message, options);

        vm.stopPrank();

        vm.prank(0x000000dE1E80ea5a234FB5488fee2584251BC7e8);
        clustersProxy.withdraw(payable(0x000000dE1E80ea5a234FB5488fee2584251BC7e8), 2 ether);
    }
}
