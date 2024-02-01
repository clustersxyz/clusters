// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ClustersBeta} from "../src/ClustersBeta.sol";
import {Base_Test} from "./Base.t.sol";

contract ClustersBetaSingleChainTest is Base_Test {
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
}
