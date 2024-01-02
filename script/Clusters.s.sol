// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
        bytes memory endpointInit =
            abi.encodeWithSignature("initialize(address,address,address)", msg.sender, SIGNER, LAYERZERO);
        IEndpoint endpointProxy = IEndpoint(address(new ERC1967Proxy(address(endpoint), endpointInit)));
        ClustersHub clusters = new ClustersHub(address(pricing), address(endpointProxy), block.timestamp + 7 days);
        endpointProxy.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
