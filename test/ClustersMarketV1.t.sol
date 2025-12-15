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
    address internal constant CHARLIE = address(0x33333);

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
        if (_randomChance(2)) result = bytes12(result);
    }

    function _smallAddress(bytes memory seed) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := and(keccak256(add(seed, 0x20), mload(seed)), 0xffffffffffffffffffffffffffffffff)
        }
    }

    struct _TestTemps {
        uint256 minBidIncrement;
        uint256 minAnnualPrice;
        uint256 spent;
        uint256 price;
        bytes32 clusterName;
        uint256 bidTimestamp;
        uint256 bidAmount;
        uint256 lastBacking;
        uint256 bidIncrement;
        uint256 bidDecrement;
        uint256 lastBidderBalanceBefore;
        uint256 lastBidAmount;
    }

    function testBuyBidPoke(bytes32) public {
        if (vm.getBlockTimestamp() == 0) {
            vm.warp(100);
        }

        vm.deal(ALICE, 2 ** 88 - 1);
        vm.deal(BOB, 2 ** 88 - 1);
        vm.deal(CHARLIE, 2 ** 88 - 1);

        vm.warp(_bound(_randomUniform(), 1, 256));

        _TestTemps memory t;
        t.minBidIncrement = market.minBidIncrement();
        t.clusterName = _randomClusterName();
        t.minAnnualPrice = pricing.minAnnualPrice();
        t.bidAmount = _bound(_random(), t.minAnnualPrice, 1 ether);

        vm.expectRevert(ClustersMarketV1.NameNotRegistered.selector);
        market.bid{value: t.bidAmount}(t.clusterName);

        vm.expectRevert(ClustersMarketV1.Insufficient.selector);
        vm.prank(ALICE);
        market.buy(t.clusterName);

        vm.expectRevert(ClustersMarketV1.Insufficient.selector);
        vm.prank(ALICE);
        market.buy{value: t.minAnnualPrice - 1}(t.clusterName);

        // Test buy.
        vm.prank(ALICE);
        market.buy{value: t.minAnnualPrice}(t.clusterName);

        ClustersMarketV1.NameInfo memory info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, 0);
        assertEq(info.bidUpdated, 0);
        assertEq(info.bidder, address(0));
        assertEq(info.backing, t.minAnnualPrice);
        assertEq(info.lastUpdated, vm.getBlockTimestamp());
        assertEq(info.lastPrice, t.minAnnualPrice);

        t.lastBacking = info.backing;
        t.bidTimestamp = vm.getBlockTimestamp() + _bound(_random(), 0, 256);
        vm.warp(t.bidTimestamp);

        (t.spent, t.price) = pricing.getIntegratedPrice(info.lastPrice, vm.getBlockTimestamp() - info.lastUpdated);

        // Test bid.
        vm.prank(BOB);
        market.bid{value: t.bidAmount}(t.clusterName);

        info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, t.bidAmount);
        assertEq(info.bidUpdated, t.bidTimestamp);
        assertEq(info.bidder, BOB);
        assertEq(info.backing, t.lastBacking - t.spent);
        assertEq(info.lastUpdated, vm.getBlockTimestamp());
        assertEq(info.lastPrice, t.minAnnualPrice);

        // Test increase bid.
        t.bidIncrement = _bound(_random(), t.minBidIncrement, t.minBidIncrement * 2);
        vm.prank(BOB);
        market.bid{value: t.bidIncrement}(t.clusterName);

        info = market.nameInfo(t.clusterName);
        assertEq(info.owner, ALICE);
        assertEq(info.bidAmount, t.bidAmount + t.bidIncrement);
        assertEq(info.bidUpdated, t.bidTimestamp);
        assertEq(info.bidder, BOB);
        assertEq(info.backing, t.lastBacking - t.spent);
        assertEq(info.lastUpdated, vm.getBlockTimestamp());
        assertEq(info.lastPrice, t.minAnnualPrice);

        // Test outbid.
        if (_randomChance(8)) {
            t.lastBidderBalanceBefore = BOB.balance;
            t.lastBidAmount = info.bidAmount;

            t.bidAmount = info.bidAmount + _bound(_random(), t.minBidIncrement, t.minBidIncrement * 2);
            vm.prank(CHARLIE);
            market.bid{value: t.bidAmount}(t.clusterName);

            info = market.nameInfo(t.clusterName);
            assertEq(info.owner, ALICE);
            assertEq(info.bidAmount, t.bidAmount);
            assertEq(info.bidUpdated, vm.getBlockTimestamp());
            assertEq(info.bidder, CHARLIE);
            assertEq(info.backing, t.lastBacking - t.spent);
            assertEq(info.lastUpdated, vm.getBlockTimestamp());
            assertEq(info.lastPrice, t.minAnnualPrice);

            assertEq(BOB.balance, t.lastBidderBalanceBefore + t.lastBidAmount);
            return;
        }
        _checkInvariants(t);

        // Test poke after name has exhausted all backing.
        if (_randomChance(8)) {
            t.lastBidderBalanceBefore = BOB.balance;
            t.lastBidAmount = info.bidAmount;

            // Test poke to send to winning bidder.
            if (_randomChance(2)) {
                vm.warp(vm.getBlockTimestamp() + 365 days);
                market.poke(t.clusterName);

                info = market.nameInfo(t.clusterName);
                assertEq(info.owner, BOB);
                assertEq(info.bidAmount, 0);
                assertEq(info.bidUpdated, 0);
                assertEq(info.bidder, address(0));
                assertEq(info.backing, t.lastBidAmount);
                assertEq(info.lastUpdated, vm.getBlockTimestamp());
                assertEq(info.lastPrice, t.minAnnualPrice);
                return;
            }

            // Test poke to send to stash if there's no bidder.
            if (_randomChance(2)) {
                vm.warp(vm.getBlockTimestamp() + market.bidTimelock());
                vm.prank(BOB);
                market.reduceBid(t.clusterName, t.lastBidAmount);

                info = market.nameInfo(t.clusterName);
                assertEq(info.bidAmount, 0);
                assertEq(info.bidUpdated, 0);
                assertEq(info.bidder, address(0));
                assertEq(info.owner, ALICE);

                vm.warp(vm.getBlockTimestamp() + 365 days);
                market.poke(t.clusterName);

                info = market.nameInfo(t.clusterName);
                assertEq(info.owner, address(uint160((info.id & 0xff) + 1)));
                assertEq(info.bidAmount, 0);
                assertEq(info.bidUpdated, 0);
                assertEq(info.bidder, address(0));
                assertEq(info.backing, 0);
                assertEq(info.lastUpdated, vm.getBlockTimestamp());
                assertEq(info.lastPrice, t.minAnnualPrice);
                return;
            }

            // Test that a better bid will auto win the name,
            if (_randomChance(2)) {
                vm.warp(vm.getBlockTimestamp() + 365 days);
                t.bidAmount = info.bidAmount + _bound(_random(), t.minBidIncrement, t.minBidIncrement * 2);

                vm.prank(CHARLIE);
                market.bid{value: t.bidAmount}(t.clusterName);

                info = market.nameInfo(t.clusterName);
                assertEq(info.owner, CHARLIE);
                assertEq(info.bidAmount, 0);
                assertEq(info.bidUpdated, 0);
                assertEq(info.bidder, address(0));
                assertEq(info.backing, t.bidAmount);
                assertEq(info.lastUpdated, vm.getBlockTimestamp());
                assertEq(info.lastPrice, t.minAnnualPrice);

                assertEq(BOB.balance, t.lastBidderBalanceBefore + t.lastBidAmount);
                return;
            }

            // Test reduce bid will poke and skip the entire reduce bid workflow.
            vm.warp(vm.getBlockTimestamp() + 365 days);
            vm.prank(BOB);
            market.reduceBid(t.clusterName, t.lastBidAmount);

            info = market.nameInfo(t.clusterName);
            assertEq(info.owner, BOB);
            assertEq(info.bidAmount, 0);
            assertEq(info.bidUpdated, 0);
            assertEq(info.bidder, address(0));
            assertEq(info.backing, t.lastBidAmount);
            assertEq(info.lastUpdated, vm.getBlockTimestamp());
            assertEq(info.lastPrice, t.minAnnualPrice);

            assertEq(BOB.balance, t.lastBidderBalanceBefore);
            return;
        }
        _checkInvariants(t);

        // Test accept bid.
        if (_randomChance(8)) {
            t.lastBidAmount = info.bidAmount;

            vm.prank(ALICE);
            market.acceptBid(t.clusterName);
            info = market.nameInfo(t.clusterName);
            assertEq(info.owner, BOB);
            assertEq(info.bidAmount, 0);
            assertEq(info.bidUpdated, 0);
            assertEq(info.bidder, address(0));
            assertEq(info.backing, t.lastBidAmount);
            assertEq(info.lastUpdated, vm.getBlockTimestamp());
            assertEq(info.lastPrice, t.minAnnualPrice);
            return;
        }
        _checkInvariants(t);

        // Test reduce bid.
        if (_randomChance(8)) {
            vm.warp(vm.getBlockTimestamp() + market.bidTimelock());
            uint256 maxDecrement = info.bidAmount - pricing.minAnnualPrice();

            t.bidDecrement = _bound(_randomUniform(), 0, maxDecrement);
            uint256 expectedBidAmount = info.bidAmount - t.bidDecrement;
            if (_randomChance(2)) {
                vm.prank(BOB);
                vm.expectRevert(ClustersMarketV1.Insufficient.selector);
                market.reduceBid(t.clusterName, maxDecrement + 1);
            }
            vm.prank(BOB);
            market.reduceBid(t.clusterName, t.bidDecrement);
            info = market.nameInfo(t.clusterName);
            assertEq(info.bidAmount, expectedBidAmount);
            assertEq(info.bidUpdated, vm.getBlockTimestamp());
            assertEq(info.bidder, BOB);
        }
        _checkInvariants(t);

        // Test refund bid.
        if (_randomChance(8)) {
            vm.warp(vm.getBlockTimestamp() + market.bidTimelock());
            uint256 delta = market.nameInfo(t.clusterName).bidAmount + _bound(_random(), 0, 256);
            vm.prank(BOB);
            market.reduceBid(t.clusterName, delta);
            info = market.nameInfo(t.clusterName);
            assertEq(info.bidAmount, 0);
            assertEq(info.bidUpdated, 0);
            assertEq(info.bidder, address(0));
        }
        _checkInvariants(t);
    }

    function _checkInvariants(_TestTemps memory t) internal view {
        ClustersMarketV1.NameInfo memory info = market.nameInfo(t.clusterName);
        uint256 totalBidBacking = market.totalBidBacking();
        assert(totalBidBacking >= info.bidAmount);
        assert(address(market).balance >= totalBidBacking);
        if (info.bidder != address(0)) {
            assert(info.bidAmount != 0);
            assert(info.bidUpdated != 0);
        } else {
            assert(info.bidAmount == 0);
            assert(info.bidUpdated == 0);
        }
    }
}
