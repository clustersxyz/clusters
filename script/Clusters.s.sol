// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

contract ClustersScript is Script {
    address constant ADMIN = address(uint160(uint256(keccak256(abi.encodePacked("ADMIN")))));
    address constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));
    address constant LAYERZERO = address(uint160(uint256(keccak256(abi.encodePacked("LAYERZERO")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger(block.timestamp);
        Endpoint endpoint = new Endpoint();
        endpoint.initialize(msg.sender, ADMIN, SIGNER, LAYERZERO);
        ClustersHub clusters = new ClustersHub(address(pricing), address(endpoint), block.timestamp + 7 days);
        endpoint.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
