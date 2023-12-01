// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {PricingMinFlatMaxLinearDecayExponential} from "../src/PricingMinFlatMaxLinearDecayExponential.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingMinFlatMaxLinearDecayExponential pricing = new PricingMinFlatMaxLinearDecayExponential();
        Endpoint endpoint = new Endpoint();
        new Clusters(address(pricing), address(endpoint));
        vm.stopBroadcast();
    }
}
