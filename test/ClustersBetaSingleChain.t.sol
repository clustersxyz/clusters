// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ClustersBeta} from "../src/ClustersBeta.sol";
import {Base_Test} from "./Base.t.sol";

contract ClustersBetaSingleChainTest is Base_Test {
    event Bid(bytes32 from, uint256 amount, bytes32 name);
    event Bid(bytes32 from, uint256 amount, bytes32 name, bytes32 referralAddress);

    ClustersBeta beta = new ClustersBeta();

    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function testBeta() public {
        beta.placeBid{value: 0.1 ether}("foobar");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        bytes32[] memory names = new bytes32[](2);
        names[0] = "foobar2";
        names[1] = "foobar3";
        beta.placeBids{value: 0.2 ether}(amounts, names);
    }

    function testLocalPlaceBid() public {
        bytes32 from = _addressToBytes32(users.alicePrimary);
        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("foobar"));
        vm.prank(users.alicePrimary);
        clustersProxy.placeBid{value: 0.1 ether}(_stringToBytes32("foobar"));
    }

    function testLocalPlaceBidWithReferral() public {
        bytes32 from = _addressToBytes32(users.alicePrimary);
        vm.expectEmit(address(clustersProxy));
        emit Bid(from, 0.1 ether, _stringToBytes32("zodomo"), _addressToBytes32(users.bobPrimary));
        vm.prank(users.alicePrimary);
        clustersProxy.placeBid{value: 0.1 ether}(_stringToBytes32("zodomo"), _addressToBytes32(users.bobPrimary));
    }

    function testLocalPlaceBids() public {
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        bytes32[] memory names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarBatch");
        names[1] = _stringToBytes32("ryeshrimpBatch");
        names[2] = _stringToBytes32("munamBatch");
        names[3] = _stringToBytes32("zodomoBatch");

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i]);
        }
        vm.prank(users.alicePrimary);
        clustersProxy.placeBids{value: 0.4 ether}(amounts, names);
    }

    function testLocalPlaceBidsWithReferral() public {
        bytes32 from = _addressToBytes32(users.alicePrimary);
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        amounts[2] = 0.1 ether;
        amounts[3] = 0.1 ether;
        bytes32[] memory names = new bytes32[](4);
        names[0] = _stringToBytes32("foobarRefer");
        names[1] = _stringToBytes32("ryeshrimpRefer");
        names[2] = _stringToBytes32("munamRefer");
        names[3] = _stringToBytes32("zodomoRefer");

        for (uint256 i; i < names.length; ++i) {
            vm.expectEmit(address(clustersProxy));
            emit Bid(from, amounts[i], names[i], _addressToBytes32(users.bobPrimary));
        }
        vm.prank(users.alicePrimary);
        clustersProxy.placeBids{value: 0.4 ether}(amounts, names, _addressToBytes32(users.bobPrimary));
    }
}
