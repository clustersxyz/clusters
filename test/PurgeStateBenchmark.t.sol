// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test} from "./Base.t.sol";

contract PurgeStateBenchmarkTest is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
        deployLocalHarberger();
        vm.warp(constants.MARKET_OPEN_TIMESTAMP() + 1 days);
    }

    function massAdd(uint256 start, uint256 end, uint256 amount) internal {
        for (start; start <= end; ++start) {
            address addr = address(uint160(uint256(keccak256(abi.encodePacked(start)))));
            vm.deal(addr, amount);
            vm.startPrank(addr);
            clusters.buyName{value: amount}(amount, string(abi.encodePacked(start)));
            clusters.add(_addressToBytes32(users.alicePrimary));
            vm.stopPrank();
        }
    }

    function testBenchmark() public {
        massAdd(1, 10000, minPrice);
        vm.prank(users.alicePrimary);
        clusters.verify(1);
    }
}
