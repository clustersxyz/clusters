// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {LibClone} from "solady/utils/LibClone.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

contract ClustersScript is Script {
    address constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));
    address constant LAYERZERO = address(uint160(uint256(keccak256(abi.encodePacked("LAYERZERO")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger(block.timestamp);
        Endpoint endpoint = new Endpoint();
        IEndpoint endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        endpointProxy.initialize(msg.sender, SIGNER, LAYERZERO);
        ClustersHub clusters = new ClustersHub(address(pricing), address(endpointProxy), block.timestamp + 7 days);
        endpointProxy.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
