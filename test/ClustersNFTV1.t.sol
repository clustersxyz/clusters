// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import "./utils/SoladyTest.sol";
import "./mocks/MockClustersNFTV1.sol";

contract ClustersNFTV1Test is SoladyTest {
    using DynamicArrayLib for *;

    MockClustersNFTV1 internal collection;

    address internal constant ALICE = address(111);
    address internal constant BOB = address(222);

    function setUp() public {
        collection = MockClustersNFTV1(LibClone.clone(address(new MockClustersNFTV1())));
        collection.initialize(address(this));
    }

    struct _TestTemps {
        DynamicArrayLib.DynamicArray clusterNames;
        DynamicArrayLib.DynamicArray recipients;
    }

    function testMintNext(bytes32) public {
        _TestTemps memory t;
        t.clusterNames = _generateClusterNames(_randomNonZeroLength());
        t.recipients = _generateRecipients(t.clusterNames.length());

        assertEq(collection.mintNext(t.clusterNames.asBytes32Array(), t.recipients.asAddressArray()), 1);

        uint256 expected = collection.totalSupply() + 1;

        uint256[] memory newClusterNames;
        do {
            newClusterNames = _generateClusterNames(_randomNonZeroLength()).data;
            newClusterNames = LibSort.difference(newClusterNames, t.clusterNames.data);
        } while (newClusterNames.length == 0);
        t.clusterNames = DynamicArrayLib.wrap(newClusterNames);
        t.recipients = _generateRecipients(t.clusterNames.length());

        assertEq(collection.mintNext(t.clusterNames.asBytes32Array(), t.recipients.asAddressArray()), expected);
    }

    function testMintAndTrasferNFTs(bytes32) public {
        _TestTemps memory t;
        t.clusterNames = _generateClusterNames(_randomNonZeroLength());
        t.recipients = _generateRecipients(t.clusterNames.length());

        collection.mintNext(t.clusterNames.asBytes32Array(), t.recipients.asAddressArray());

        vm.prank(ALICE);
        collection.setApprovalForAll(address(this), true);
        vm.prank(BOB);
        collection.setApprovalForAll(address(this), true);
        do {
            unchecked {
                for (uint256 i; i != t.clusterNames.length(); ++i) {
                    if (_randomChance(2)) {
                        address recipient = _randomChance(2) ? ALICE : BOB;
                        collection.transferFrom(collection.ownerOf(i + 1), recipient, i + 1);
                        t.recipients.set(i, recipient);
                    }
                }
                _checkInvariants(t);
            }
        } while (_randomChance(2));
    }

    function _checkInvariants(_TestTemps memory t) internal {
        unchecked {
            if (_randomChance(2)) {
                for (uint256 i; i != t.clusterNames.length(); ++i) {
                    assertEq(collection.ownerOf(i + 1), t.recipients.getAddress(i));
                    assertEq(collection.clusterNameOf(i + 1), t.clusterNames.getBytes32(i));
                }
            }
            uint256[] memory bobIds = collection.tokensOfOwner(BOB);
            uint256[] memory aliceIds = collection.tokensOfOwner(ALICE);
            if (_randomChance(2)) {
                for (uint256 i; i != aliceIds.length; ++i) {
                    assertEq(collection.ownerOf(aliceIds.get(i)), ALICE);
                    assertEq(aliceIds.get(i), collection.tokenOfOwnerByIndex(ALICE, i));
                }
                for (uint256 i; i != bobIds.length; ++i) {
                    assertEq(collection.ownerOf(bobIds.get(i)), BOB);
                    assertEq(bobIds.get(i), collection.tokenOfOwnerByIndex(BOB, i));
                }
            }
            if (_randomChance(2)) {
                LibSort.sort(aliceIds);
                LibSort.sort(bobIds);
                uint256[] memory allIds = LibSort.union(aliceIds, bobIds);
                assertEq(allIds.length, collection.totalSupply());
                for (uint256 i; i != allIds.length; ++i) {
                    uint256 id = allIds.get(i);
                    bytes32 clusterName = collection.clusterNameOf(id);
                    assertEq(id, collection.idOf(clusterName));
                }
            }
        }
    }

    function _randomBigLength() internal returns (uint256) {
        return _random() & 1023;
    }

    function _randomBigNonZeroLength() internal returns (uint256 result) {
        while (result == 0) result = _randomBigLength();
    }

    function _randomSmallLength() internal returns (uint256) {
        return _random() & 15;
    }

    function _randomSmallNonZeroLength() internal returns (uint256 result) {
        while (result == 0) result = _randomSmallLength();
    }

    function _randomLength() internal returns (uint256) {
        return _randomChance(128) ? _randomBigLength() : _randomSmallLength();
    }

    function _randomNonZeroLength() internal returns (uint256 result) {
        while (result == 0) result = _randomLength();
    }

    function _generateClusterNames(uint256 n) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                uint256 r = _random();
                if (r == 0) r = 1;
                a.set(i, r);
            }
        }
        LibSort.sort(a.data);
        LibSort.uniquifySorted(a.data);
    }

    function _generateRecipients(uint256 n) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                a.set(i, uint160(_randomChance(2) ? ALICE : BOB));
            }
        }
    }

    function testSetAndGetClustersData(bytes32) public {
        do {
            uint40 id0 = uint40(_random());
            uint40 id1 = uint40(_random());
            uint256 ownedIndex0 = _random();
            uint256 ownedIndex1 = _random();
            uint208 additionalData0 = uint208(_random());
            uint208 additionalData1 = uint208(_random());

            collection.clustersDataInitialize(0, id0, ownedIndex0);
            collection.clustersDataInitialize(1, id1, ownedIndex1);
            assertEq(collection.clustersDataGetId(0), id0);
            assertEq(collection.clustersDataGetId(1), id1);
            assertEq(collection.clustersDataGetOwnedIndex(0), ownedIndex0);
            assertEq(collection.clustersDataGetOwnedIndex(1), ownedIndex1);

            collection.clustersDataSetAdditionalData(0, additionalData0);
            collection.clustersDataSetAdditionalData(1, additionalData1);
            assertEq(collection.clustersDataGetAdditionalData(0), additionalData0);
            assertEq(collection.clustersDataGetAdditionalData(1), additionalData1);

            ownedIndex0 = _random();
            ownedIndex1 = _random();
            additionalData0 = uint208(_random());
            additionalData1 = uint208(_random());

            collection.clustersDataSetOwnedIndex(0, ownedIndex0);
            collection.clustersDataSetOwnedIndex(1, ownedIndex1);
            assertEq(collection.clustersDataGetId(0), id0);
            assertEq(collection.clustersDataGetId(1), id1);
            assertEq(collection.clustersDataGetOwnedIndex(0), ownedIndex0);
            assertEq(collection.clustersDataGetOwnedIndex(1), ownedIndex1);

            collection.clustersDataSetAdditionalData(0, additionalData0);
            collection.clustersDataSetAdditionalData(1, additionalData1);
            assertEq(collection.clustersDataGetAdditionalData(0), additionalData0);
            assertEq(collection.clustersDataGetAdditionalData(1), additionalData1);
        } while (_randomChance(2));
    }
}
