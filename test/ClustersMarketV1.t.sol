// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import {PricingFlat} from "clusters/PricingFlat.sol";
import "./utils/SoladyTest.sol";
import "./mocks/MockClustersNFTV1.sol";
import "./mocks/MockClustersMarketV1.sol";

contract ClustersMarketV1Test is SoladyTest {
    using DynamicArrayLib for *;

    PricingFlat internal pricing;
    MockClustersNFTV1 internal nft;
    MockClustersMarketV1 internal market;

    address internal constant ALICE = address(111);
    address internal constant BOB = address(222);

    function setUp() public {
        pricing = PricingFlat(_smallAddress("pricing"));
        vm.etch(address(pricing), LibClone.clone(address(new PricingFlat())).code);
        nft = MockClustersNFTV1(_smallAddress("nft"));
        vm.etch(address(nft), LibClone.clone(address(new MockClustersNFTV1())).code);
        market = MockClustersMarketV1(LibClone.clone(address(new MockClustersMarketV1())));
        market.initialize(address(this));
        nft.initialize(address(this));
        market.setPricingContract(address(pricing));
        market.setNFTContract(address(nft));
    }

    function testSetContractAddresses(address nftContract, address pricingContract) public {
        if (uint160(nftContract) > type(uint128).max) {
            nftContract = _smallAddress(abi.encode(nftContract));
        }
        if (uint160(pricingContract) > type(uint128).max) {
            pricingContract = _smallAddress(abi.encode(pricingContract));
        }
        market.setNFTContract(nftContract);
        market.setPricingContract(pricingContract);
        assertEq(market.nftContract(), nftContract);
        assertEq(market.pricingContract(), pricingContract);
    }

    function testGetIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsSinceUpdate) public view {
        lastUpdatedPrice = _bound(lastUpdatedPrice, 0, 0xffffffffffffffffffffffffffffffff);
        secondsSinceUpdate = _bound(secondsSinceUpdate, 0, 0xffffffff);
        (uint256 spent, uint256 price) = market.getIntegratedPrice(lastUpdatedPrice, secondsSinceUpdate);
        (uint256 expectedSpent, uint256 expectedPrice) =
            pricing.getIntegratedPrice(lastUpdatedPrice, secondsSinceUpdate);
        assertEq(spent, expectedSpent);
        assertEq(price, expectedPrice);
    }

    function testIsRegistered(bytes32) public {
        bytes32 clusterName = _randomClusterName();
        assertEq(market.isRegistered(clusterName), true);
        if (_randomChance(2)) {
            nft.mintNext(clusterName, address(uint160(_bound(_randomUniform(), 1, 256))));
            assertEq(market.isRegistered(clusterName), true);
            return;
        }
        if (_randomChance(2)) {
            nft.mintNext(clusterName, address(uint160(_bound(_randomUniform(), 257, 0xffffffff))));
            assertEq(market.isRegistered(clusterName), false);
        }
    }

    function _randomClusterName() internal returns (bytes32 result) {
        do {
            result = bytes32(_random());
        } while (LibString.normalizeSmallString(result) != result || result == bytes32(0));
    }

    function _smallAddress(bytes memory seed) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := and(keccak256(add(seed, 0x20), mload(seed)), 0xffffffffffffffffffffffffffffffff)
        }
    }
}
