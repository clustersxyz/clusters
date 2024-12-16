// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./utils/SoladyTest.sol";
import "./mocks/MockClustersNFTV1.sol";

contract ClustersNFTV1Test is SoladyTest {
    using DynamicArrayLib for *;

    MockClustersNFTV1 internal nft;

    address internal constant ALICE = address(111);
    address internal constant BOB = address(222);

    function setUp() public {
        nft = MockClustersNFTV1(LibClone.clone(address(new MockClustersNFTV1())));
        nft.initialize(address(this));
    }

    struct _TestTemps {
        DynamicArrayLib.DynamicArray clusterNames;
        DynamicArrayLib.DynamicArray recipients;
    }

    function testInitialDataAndLinkedAddress(bytes32) public {
        ClustersNFTV1.Mint[] memory mints = new ClustersNFTV1.Mint[](1);
        mints[0].clusterName = _randomClusterName();
        mints[0].to = _randomRecipient();
        mints[0].initialTimestamp = _bound(_random(), 0, type(uint40).max);
        mints[0].initialBacking = _bound(_random(), 0, type(uint88).max);
        assertEq(nft.mintNext(mints), 1);
        (uint256 initialTimestamp, uint256 initialBacking) = nft.initialData(mints[0].clusterName);
        assertEq(initialTimestamp, mints[0].initialTimestamp);
        assertEq(initialBacking, mints[0].initialBacking);
        assertEq(nft.linkedAddress(mints[0].clusterName), address(0));
        address linkedAddress = _randomAddress();
        vm.prank(mints[0].to);
        nft.setLinkedAddress(mints[0].clusterName, linkedAddress);
        (initialTimestamp, initialBacking) = nft.initialData(mints[0].clusterName);
        assertEq(initialTimestamp, mints[0].initialTimestamp);
        assertEq(initialBacking, mints[0].initialBacking);
        assertEq(nft.linkedAddress(mints[0].clusterName), linkedAddress);
    }

    function testMintNext(bytes32) public {
        _TestTemps memory t;
        t.clusterNames = _randomClusterNames(_randomNonZeroLength());
        t.recipients = _randomRecipients(t.clusterNames.length());

        assertEq(nft.mintNext(_toMints(t.clusterNames, t.recipients)), 1);

        uint256 expected = nft.totalSupply() + 1;

        uint256[] memory newClusterNames;
        do {
            newClusterNames = _randomClusterNames(_randomNonZeroLength()).data;
            newClusterNames = LibSort.difference(newClusterNames, t.clusterNames.data);
        } while (newClusterNames.length == 0);
        t.clusterNames = DynamicArrayLib.wrap(newClusterNames);
        t.recipients = _randomRecipients(t.clusterNames.length());

        assertEq(nft.mintNext(_toMints(t.clusterNames, t.recipients)), expected);
    }

    function testMintAndTrasferNFTs(bytes32) public {
        _TestTemps memory t;
        t.clusterNames = _randomClusterNames(_randomNonZeroLength());
        t.recipients = _randomRecipients(t.clusterNames.length());

        nft.mintNext(_toMints(t.clusterNames, t.recipients));

        vm.prank(ALICE);
        nft.setApprovalForAll(address(this), true);
        vm.prank(BOB);
        nft.setApprovalForAll(address(this), true);
        do {
            unchecked {
                for (uint256 i; i != t.clusterNames.length(); ++i) {
                    if (_randomChance(2)) {
                        address recipient = _randomChance(2) ? ALICE : BOB;
                        nft.transferFrom(nft.ownerOf(i + 1), recipient, i + 1);
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
                    assertEq(nft.ownerOf(i + 1), t.recipients.getAddress(i));
                    assertEq(nft.nameOf(i + 1), t.clusterNames.getBytes32(i));
                }
            }
            uint256[] memory bobIds = nft.tokensOfOwner(BOB);
            uint256[] memory aliceIds = nft.tokensOfOwner(ALICE);
            if (_randomChance(2)) {
                for (uint256 i; i != aliceIds.length; ++i) {
                    assertEq(nft.ownerOf(aliceIds.get(i)), ALICE);
                    assertEq(aliceIds.get(i), nft.tokenOfOwnerByIndex(ALICE, i));
                }
                for (uint256 i; i != bobIds.length; ++i) {
                    assertEq(nft.ownerOf(bobIds.get(i)), BOB);
                    assertEq(bobIds.get(i), nft.tokenOfOwnerByIndex(BOB, i));
                }
            }
            if (_randomChance(2)) {
                LibSort.sort(aliceIds);
                LibSort.sort(bobIds);
                uint256[] memory allIds = LibSort.union(aliceIds, bobIds);
                assertEq(allIds.length, nft.totalSupply());
                for (uint256 i; i != allIds.length; ++i) {
                    uint256 id = allIds.get(i);
                    bytes32 clusterName = nft.nameOf(id);
                    (uint256 retrievedId,,) = nft.infoOf(clusterName);
                    assertEq(id, retrievedId);
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

    function _randomClusterNames(uint256 maxLength) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(maxLength);
        unchecked {
            for (uint256 i; i != maxLength; ++i) {
                a.set(i, _randomClusterName());
            }
        }
        LibSort.sort(a.data);
        LibSort.uniquifySorted(a.data);
    }

    function _randomRecipients(uint256 n) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                a.set(i, _randomRecipient());
            }
        }
    }

    function _toMints(DynamicArrayLib.DynamicArray memory names, DynamicArrayLib.DynamicArray memory recipients)
        internal
        pure
        returns (ClustersNFTV1.Mint[] memory a)
    {
        a = new ClustersNFTV1.Mint[](names.length());
        assertEq(names.length(), recipients.length());
        unchecked {
            for (uint256 i; i != names.length(); ++i) {
                a[i].clusterName = names.getBytes32(i);
                a[i].to = recipients.getAddress(i);
            }
        }
    }

    function testSetAndGetClustersData(bytes32) public {
        do {
            uint40 id0 = uint40(_random());
            uint40 id1 = uint40(_random());
            uint256 ownedIndex0 = _random();
            uint256 ownedIndex1 = _random();
            uint168 additionalData0 = uint168(_random());
            uint168 additionalData1 = uint168(_random());

            nft.nameDataInitialize(0, id0, ownedIndex0);
            nft.nameDataInitialize(1, id1, ownedIndex1);
            assertEq(nft.nameDataGetId(0), id0);
            assertEq(nft.nameDataGetId(1), id1);
            assertEq(nft.nameDataGetOwnedIndex(0), ownedIndex0);
            assertEq(nft.nameDataGetOwnedIndex(1), ownedIndex1);

            nft.nameDataSetAdditionalData(0, additionalData0);
            nft.nameDataSetAdditionalData(1, additionalData1);
            assertEq(nft.nameDataGetAdditionalData(0), additionalData0);
            assertEq(nft.nameDataGetAdditionalData(1), additionalData1);

            ownedIndex0 = _random();
            ownedIndex1 = _random();
            additionalData0 = uint168(_random());
            additionalData1 = uint168(_random());

            nft.nameDataSetOwnedIndex(0, ownedIndex0);
            nft.nameDataSetOwnedIndex(1, ownedIndex1);
            assertEq(nft.nameDataGetId(0), id0);
            assertEq(nft.nameDataGetId(1), id1);
            assertEq(nft.nameDataGetOwnedIndex(0), ownedIndex0);
            assertEq(nft.nameDataGetOwnedIndex(1), ownedIndex1);

            nft.nameDataSetAdditionalData(0, additionalData0);
            nft.nameDataSetAdditionalData(1, additionalData1);
            assertEq(nft.nameDataGetAdditionalData(0), additionalData0);
            assertEq(nft.nameDataGetAdditionalData(1), additionalData1);
        } while (_randomChance(2));
    }

    function _randomClusterName() internal returns (bytes32 result) {
        do {
            result = bytes32(
                0x6161616161616161616161616161616161616161616161616161616161616161
                    | (_randomUniform() & 0x0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e)
            );
        } while (LibString.normalizeSmallString(result) != result || result == bytes32(0));
    }

    function _randomRecipient() internal returns (address) {
        return _randomChance(2) ? ALICE : BOB;
    }
}
