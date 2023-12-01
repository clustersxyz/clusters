// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {IClusters} from "../src/IClusters.sol";

contract GasBenchmarkTest is Test {
    Pricing public pricing;
    Clusters public clusters;

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
        vm.deal(address(this), 1 ether);
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function testBenchmark() public {
        bytes32 callerSalt = "caller";
        bytes32 addrSalt = "addr";
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();
    }
}