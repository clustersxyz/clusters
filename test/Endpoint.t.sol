// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

contract EndpointTest is Test {
    PricingHarberger public pricing;
    Endpoint public endpoint;
    Clusters public clusters;
    uint256 public minPrice;

    address constant SIGNER = address(uint160(uint256(keccak256(abi.encodePacked("SIGNER")))));

    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(address(this), SIGNER);
        clusters = new Clusters(address(pricing), address(endpoint), address(this));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }
}
