// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

contract GasBenchmarkTest is Test {
    PricingHarberger public pricing;
    Endpoint public endpoint;
    Clusters public clusters;
    uint256 public minPrice;

    uint256 public immutable SIGNER_KEY = uint256(keccak256(abi.encodePacked("SIGNER")));
    address public immutable SIGNER = vm.addr(SIGNER_KEY);

    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(address(this), SIGNER);
        clusters = new Clusters(address(pricing), address(endpoint), block.timestamp);
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    function testBenchmark() public {
        bytes32 callerSalt = "caller";
        bytes32 addrSalt = "addr";
        bytes32 bidderSalt = "bidder";
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);
        address bidder = _bytesToAddress(bidderSalt);

        vm.startPrank(caller);
        vm.deal(caller, minPrice);
        clusters.create();
        clusters.add(addrBytes);
        clusters.buyName{value: minPrice}(minPrice, "foobar");
        vm.stopPrank();

        vm.startPrank(bidder);
        vm.deal(bidder, 1 ether);
        // TODO: Should people be able to bid on names without owning a cluster themselves?
        clusters.create();
        clusters.bidName{value: 0.5 ether}(0.5 ether, "foobar");
        vm.warp(block.timestamp + 30 days);
        clusters.pokeName("foobar");
        vm.stopPrank();
    }
}
