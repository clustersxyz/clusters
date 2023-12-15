// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

contract ClustersScript is Script {
    address internal constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));
    // TODO: UPDATE LAYERZERO ENDPOINT HANDLING
    address internal constant LAYERZERO = address(uint160(uint256(keccak256(abi.encodePacked("LAYERZERO")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger();
        Endpoint endpoint = new Endpoint(msg.sender, SIGNER, LAYERZERO);
        ClustersHub clusters = new ClustersHub(address(pricing), address(endpoint), block.timestamp + 7 days);
        endpoint.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
