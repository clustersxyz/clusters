// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
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
        bytes memory endpointInit =
            abi.encodeWithSignature("initialize(address,address,address,address)", msg.sender, ADMIN, SIGNER, LAYERZERO);
        IEndpoint endpointProxy =
            IEndpoint(address(new TransparentUpgradeableProxy(address(endpoint), ADMIN, endpointInit)));
        ClustersHub clusters = new ClustersHub(address(pricing), address(endpointProxy), block.timestamp + 7 days);
        endpointProxy.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
