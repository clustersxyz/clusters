// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

contract CounterScript is Script {
    address constant LZENDPOINT = address(uint160(uint256(keccak256(abi.encode("lzEndpoint")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger();
        Endpoint endpoint = new Endpoint(LZENDPOINT);
        new Clusters(address(pricing), address(endpoint));
        vm.stopBroadcast();
    }
}
