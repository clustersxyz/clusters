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

    address internal constant ALICE = address(0x11111);
    address internal constant BOB = address(0x22222);

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

        nft.setRole(address(market), nft.MINTER_ROLE(), true);
        nft.setRole(address(market), nft.CONDUIT_ROLE(), true);
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

    function testMinAnnualPrice() public view {
        assertEq(market.minAnnualPrice(), market.minAnnualPrice());
    }

    function testIsRegistered(bytes32) public {
        bytes32 clusterName = _randomClusterName();
        uint256 minAnnualPrice = pricing.minAnnualPrice();

        assertEq(market.isRegistered(clusterName), false);

        vm.deal(ALICE, 2 ** 160 - 1);
        vm.prank(ALICE);
        market.buy{value: minAnnualPrice}(clusterName);

        assertEq(market.isRegistered(clusterName), true);

        if (_randomChance(2)) {
            market.directMove(clusterName, address(uint160(_bound(_randomUniform(), 1, 256))));
            assertEq(market.isRegistered(clusterName), false);
            return;
        }
        if (_randomChance(2)) {
            market.directMove(clusterName, address(uint160(_bound(_randomUniform(), 257, 0xffffffff))));
            assertEq(market.isRegistered(clusterName), true);
        }
    }

    function _randomClusterName() internal returns (bytes32 result) {
        do {
            uint256 m = 0x6161616161616161616161616161616161616161616161616161616161616161;
            m |= _randomUniform() & 0x0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e;
            m <<= (_randomUniform() & 31) << 3;
            result = bytes32(m);
        } while (LibString.normalizeSmallString(result) != result || result == bytes32(0));
    }

    function _smallAddress(bytes memory seed) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := and(keccak256(add(seed, 0x20), mload(seed)), 0xffffffffffffffffffffffffffffffff)
        }
    }

    struct _TestTemps {
        uint256 minAnnualPrice;
        uint256 spent;
        uint256 price;
        bytes32 clusterName;
        uint256 bidTimestamp;
        uint256 bidAmount;
        uint256 lastBacking;
        uint256 bidIncrement;
    }

    function testBuyAndBidName(bytes32) public {
        vm.deal(ALICE, 2 ** 88 - 1);
        vm.deal(BOB, 2 ** 88 - 1);

        vm.warp(_bound(_randomUniform(), 1, 256));

        _TestTemps memory t;
        t.clusterName = _randomClusterName();
        t.minAnnualPrice = pricing.minAnnualPrice();
        t.bidAmount = _bound(_random(), t.minAnnualPrice, address(BOB).balance / 8);

        vm.expectRevert(ClustersMarketV1.NameNotRegistered.selector);
        market.bid{value: t.bidAmount}(t.clusterName);

        vm.expectRevert(ClustersMarketV1.Insufficient.selector);
        vm.prank(ALICE);
        market.buy(t.clusterName);

        vm.expectRevert(ClustersMarketV1.Insufficient.selector);
        vm.prank(ALICE);
        market.buy{value: t.minAnnualPrice - 1}(t.clusterName);

        vm.prank(ALICE);
        market.buy{value: t.minAnnualPrice}(t.clusterName);

        ClustersMarketV1.NameInfo memory info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, 0);
        assertEq(info.bidUpdated, 0);
        assertEq(info.bidder, address(0));
        assertEq(info.backing, t.minAnnualPrice);
        assertEq(info.lastUpdated, block.timestamp);
        assertEq(info.lastPrice, t.minAnnualPrice);

        t.lastBacking = info.backing;
        t.bidTimestamp = block.timestamp + _bound(_randomUniform(), 0, 256);
        vm.warp(t.bidTimestamp);

        (t.spent, t.price) = pricing.getIntegratedPrice(info.lastPrice, block.timestamp - info.lastUpdated);

        vm.prank(BOB);
        market.bid{value: t.bidAmount}(t.clusterName);

        info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, t.bidAmount);
        assertEq(info.bidUpdated, t.bidTimestamp);
        assertEq(info.bidder, BOB);
        assertEq(info.backing, t.lastBacking - t.spent);
        assertEq(info.lastUpdated, block.timestamp);
        assertEq(info.lastPrice, t.minAnnualPrice);

        // Test increase bid.
        t.bidIncrement = market.minBidIncrement();
        vm.prank(BOB);
        market.bid{value: t.bidIncrement}(t.clusterName);

        info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, t.bidAmount + t.bidIncrement);
        assertEq(info.bidUpdated, t.bidTimestamp);
        assertEq(info.bidder, BOB);
        assertEq(info.backing, t.lastBacking - t.spent);
        assertEq(info.lastUpdated, block.timestamp);
        assertEq(info.lastPrice, t.minAnnualPrice);
    }
}
