// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {Pricing} from "../src/Pricing.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        Pricing pricing = new Pricing();
        Endpoint endpoint = new Endpoint();
        Clusters clusters = new Clusters(address(pricing), address(endpoint));
        vm.stopBroadcast();
    }
}
