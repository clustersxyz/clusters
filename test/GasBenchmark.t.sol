// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {IClusters} from "../src/IClusters.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;

}