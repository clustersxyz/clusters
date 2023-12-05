// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

contract EndpointTest is Test {
    address constant LZENDPOINT = address(uint160(uint256(keccak256(abi.encode("lzEndpoint")))));

    PricingHarberger public pricing;
    Endpoint public endpoint;
    Clusters public clusters;
    uint256 public minPrice;

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(LZENDPOINT);
        clusters = new Clusters(address(pricing), address(endpoint));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }
}
