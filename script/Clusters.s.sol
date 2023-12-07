// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

contract CounterScript is Script {
    address constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger();
        Endpoint endpoint = new Endpoint(address(this), SIGNER);
        new Clusters(address(pricing), address(endpoint), block.timestamp);
        vm.stopBroadcast();
    }
}
