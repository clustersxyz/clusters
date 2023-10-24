// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
    }
}
