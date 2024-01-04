// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {LibClone} from "solady/utils/LibClone.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {IPricing} from "../src/interfaces/IPricing.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

interface IInitialize {
    function initialize(address owner_, uint256 protocolDeployTimestamp_) external;
}

contract ClustersScript is Script {
    address constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));
    address constant LAYERZERO = address(uint160(uint256(keccak256(abi.encodePacked("LAYERZERO")))));

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PricingHarberger pricing = new PricingHarberger();
        IPricing pricingProxy = IPricing(LibClone.deployERC1967(address(pricing)));
        PricingHarberger(address(pricingProxy)).initialize(msg.sender, block.timestamp + 7 days);
        Endpoint endpoint = new Endpoint();
        IEndpoint endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        Endpoint(address(endpointProxy)).initialize(msg.sender, SIGNER, LAYERZERO);
        ClustersHub clusters = new ClustersHub(address(pricingProxy), address(endpointProxy), block.timestamp + 7 days);
        endpointProxy.setClustersAddr(address(clusters));
        vm.stopBroadcast();
    }
}
