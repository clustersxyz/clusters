// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters} from "../src/Clusters.sol";

contract ClustersTest is Test {
    Clusters public clusters;

    function setUp() public {
        clusters = new Clusters();
    }
}
