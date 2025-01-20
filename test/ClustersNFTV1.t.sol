// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./utils/SoladyTest.sol";
import "./mocks/MockClustersNFTV1.sol";
import "./mocks/MockClustersNFTBaseURIRenderer.sol";

contract ClustersNFTV1Test is SoladyTest {
    using DynamicArrayLib for *;

    MockClustersNFTV1 internal nft;
    MockClustersNFTBaseURIRenderer internal tokenURIRenderer;

    address internal constant ALICE = address(111);
    address internal constant BOB = address(222);

    function setUp() public {
        nft = MockClustersNFTV1(LibClone.clone(address(new MockClustersNFTV1())));
        nft.initialize(address(this));
        tokenURIRenderer = new MockClustersNFTBaseURIRenderer();
        tokenURIRenderer.setOwner(address(this));
    }

    function testSeedGas() public {
        vm.pauseGasMetering();
        ClustersNFTV1.Mint[] memory mints = _randomSeeds();
        vm.resumeGasMetering();
        nft.mintNext(mints);
    }

    function _randomSeeds() internal returns (ClustersNFTV1.Mint[] memory mints) {
        uint256 n = 100;
        bytes32[] memory clusterNames = new bytes32[](n);
        mints = new ClustersNFTV1.Mint[](n);
        for (uint256 i; i < mints.length; ++i) {
            ClustersNFTV1.Mint memory mint = mints[i];
            mint.clusterName = bytes12(_randomClusterName());
            mint.to = _randomNonZeroAddress();
            mint.initialTimestamp = _bound(_random(), 0, type(uint40).max);
            mint.initialBacking = _bound(_random(), 0, type(uint88).max);
            clusterNames[i] = mint.clusterName;
        }
        LibSort.sort(clusterNames);
        if (clusterNames.length != n) return _randomSeeds();
    }

    function testTokenURI(address to, uint256 id) public {
        if (to == address(0)) to = _randomNonZeroAddress();
        nft.directMint(to, id);
        nft.setTokenURIRenderer(address(tokenURIRenderer));
        tokenURIRenderer.setBaseURI("https://hehe.org/{id}.json");
        string memory expected = string(abi.encodePacked("https://hehe.org/", LibString.toString(id), ".json"));
        assertEq(nft.tokenURI(id), expected);
    }

    struct _TestTemps {
        DynamicArrayLib.DynamicArray clusterNames;
        DynamicArrayLib.DynamicArray recipients;
        DynamicArrayLib.DynamicArray initialTimestamps;
        DynamicArrayLib.DynamicArray initialBackings;
        DynamicArrayLib.DynamicArray linkedAddresses;
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
        _TestTemps memory t = _randomTestTemps();

        assertEq(nft.mintNext(_toMints(t)), 1);

        uint256 expected = nft.totalSupply() + 1;

        uint256[] memory newClusterNames;
        do {
            newClusterNames = _randomClusterNames(_randomNonZeroLength()).data;
            newClusterNames = LibSort.difference(newClusterNames, t.clusterNames.data);
        } while (newClusterNames.length == 0);
        t.clusterNames = DynamicArrayLib.wrap(newClusterNames);
        t.recipients = _randomRecipients(t.clusterNames.length());
        t.initialBackings = _randomInitialBackings(t.clusterNames.length());
        t.initialTimestamps = _randomInitialTimestamps(t.clusterNames.length());

        assertEq(nft.mintNext(_toMints(t)), expected);
    }

    function testMixed(bytes32) public {
        _TestTemps memory t = _randomTestTemps();

        assertEq(nft.defaultId(ALICE), 0);
        assertEq(nft.defaultId(BOB), 0);

        nft.mintNext(_toMints(t));

        if (_randomChance(8)) {
            if (nft.balanceOf(ALICE) > 0) {
                assertEq(nft.defaultId(ALICE), nft.tokensOfOwner(ALICE)[0]);
            }
            if (nft.balanceOf(BOB) > 0) {
                assertEq(nft.defaultId(BOB), nft.tokensOfOwner(BOB)[0]);
            }
        }

        do {
            if (_randomChance(2)) _testTransferForm(t);
            if (_randomChance(2)) _checkInvariants(t);
            if (_randomChance(8)) _testInitialDataAndSetAndGetLinkedAddresses(t);
            if (_randomChance(2)) _testSetAndGetDefaultId(t);
        } while (_randomChance(2));
    }

    function _testTransferForm(_TestTemps memory t) internal {
        uint256 newTimestamp = vm.getBlockTimestamp() + (_random() % 100);
        vm.warp(newTimestamp);
        for (uint256 i; i < t.clusterNames.length(); ++i) {
            if (_randomChance(2)) {
                address recipient = _randomChance(2) ? ALICE : BOB;
                uint256 id = i + 1;
                address owner = nft.ownerOf(id);
                vm.prank(owner);
                nft.transferFrom(owner, recipient, id);
                t.recipients.set(i, recipient);

                bytes32 clusterName = nft.nameOf(id);
                assertEq(clusterName, t.clusterNames.getBytes32(i));
                (uint256 retrievedId,, uint256 startTimestamp) = nft.infoOf(clusterName);
                assertEq(retrievedId, id);
                if (owner != recipient) {
                    assertEq(startTimestamp, newTimestamp);
                }
            }
        }
    }

    function _testInitialDataAndSetAndGetLinkedAddresses(_TestTemps memory t) internal {
        _checkInitialData(t);
        for (uint256 i; i < t.clusterNames.length(); ++i) {
            if (_randomChance(2)) {
                address newLinkedAddress = _randomAddress();
                address owner = nft.ownerOf(i + 1);
                vm.prank(owner);
                nft.setLinkedAddress(t.clusterNames.getBytes32(i), newLinkedAddress);
                t.linkedAddresses.set(i, newLinkedAddress);
            }
        }
        _checkInitialData(t);
    }

    function _testSetAndGetDefaultId(_TestTemps memory t) internal {
        uint256 n = t.clusterNames.length();
        address owner = t.recipients.getAddress(_randomUniform() % n);
        uint256 id = _bound(_randomUniform(), 0, n + 10);
        vm.prank(owner);
        nft.setDefaultId(id);
        if (nft.nameOf(id) != "" && nft.ownerOf(id) == owner) {
            assertEq(nft.defaultId(owner), id);
        } else if (nft.balanceOf(owner) != 0) {
            assertEq(nft.defaultId(owner), nft.tokensOfOwner(owner)[0]);
        }
    }

    function _checkInitialData(_TestTemps memory t) internal view {
        for (uint256 i; i < t.clusterNames.length(); ++i) {
            bytes32 clusterName = t.clusterNames.getBytes32(i);
            (uint256 initialTimestamp, uint256 initialBacking) = nft.initialData(clusterName);
            assertEq(initialTimestamp, t.initialTimestamps.get(i));
            assertEq(initialBacking, t.initialBackings.get(i));
            assertEq(nft.linkedAddress(clusterName), t.linkedAddresses.getAddress(i));
        }
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

    function _randomTestTemps() internal returns (_TestTemps memory t) {
        t.clusterNames = _randomClusterNames(_randomNonZeroLength());
        t.recipients = _randomRecipients(t.clusterNames.length());
        t.initialTimestamps = _randomInitialTimestamps(t.clusterNames.length());
        t.initialBackings = _randomInitialBackings(t.clusterNames.length());
        t.linkedAddresses.resize(t.clusterNames.length());
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

    function _randomInitialTimestamps(uint256 n) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                a.set(i, _bound(_random(), 0, 2 ** 40 - 1));
            }
        }
    }

    function _randomInitialBackings(uint256 n) internal returns (DynamicArrayLib.DynamicArray memory a) {
        a.resize(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                a.set(i, _bound(_random(), 0, 2 ** 88 - 1));
            }
        }
    }

    function _toMints(_TestTemps memory t) internal pure returns (ClustersNFTV1.Mint[] memory) {
        return _toMints(t.clusterNames, t.recipients, t.initialTimestamps, t.initialBackings);
    }

    function _toMints(
        DynamicArrayLib.DynamicArray memory names,
        DynamicArrayLib.DynamicArray memory recipients,
        DynamicArrayLib.DynamicArray memory initialTimestamps,
        DynamicArrayLib.DynamicArray memory initialBackings
    ) internal pure returns (ClustersNFTV1.Mint[] memory a) {
        a = new ClustersNFTV1.Mint[](names.length());
        assertEq(names.length(), recipients.length());
        for (uint256 i; i < names.length(); ++i) {
            ClustersNFTV1.Mint memory mint = a[i];
            mint.clusterName = names.getBytes32(i);
            mint.to = recipients.getAddress(i);
            mint.initialTimestamp = initialTimestamps.get(i);
            mint.initialBacking = initialBackings.get(i);
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
            uint256 m = 0x6161616161616161616161616161616161616161616161616161616161616161;
            m |= _randomUniform() & 0x0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e;
            m <<= (_randomUniform() & 31) << 3;
            result = bytes32(m);
        } while (LibString.normalizeSmallString(result) != result || result == bytes32(0));
    }

    function _randomRecipient() internal returns (address) {
        return _randomChance(2) ? ALICE : BOB;
    }
}
