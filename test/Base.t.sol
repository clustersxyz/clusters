// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//import "layerzero-oapp/test/TestHelper.sol";
import "devtools/mocks/EndpointV2Mock.sol";
import "forge-std/Test.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
import {OAppUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppUpgradeable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Utils} from "./utils/Utils.sol";

import {IPricing} from "clusters/interfaces/IPricing.sol";
import {IEndpoint} from "clusters/interfaces/IEndpoint.sol";
import {IClustersHub} from "clusters/interfaces/IClustersHub.sol";

import {PricingFlat} from "clusters/PricingFlat.sol";
import {PricingHarbergerHarness} from "./harness/PricingHarbergerHarness.sol";
import {Endpoint} from "clusters/Endpoint.sol";
import {ClustersHub} from "clusters/ClustersHub.sol";

import {FickleReceiver} from "./mocks/FickleReceiver.sol";
import {Constants} from "./utils/Constants.sol";
import {Users} from "./utils/Types.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LibString} from "solady/utils/LibString.sol";
import {console2} from "forge-std/Test.sol";

abstract contract Base_Test is Test, Utils {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LibString for uint256;

    /// VARIABLES ///

    Users internal users;
    uint256 internal minPrice;
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set vals) internal values;

    /// TEST CONTRACTS ///

    EndpointV2Mock internal eid1;
    EndpointV2Mock internal eid2;

    Constants internal constants;
    PricingFlat internal pricingFlat;
    PricingHarbergerHarness internal pricingHarberger;
    IEndpoint internal endpoint;
    IClustersHub internal clusters;
    FickleReceiver internal fickleReceiver;
    IEndpoint internal endpointProxy;
    IPricing internal pricingProxy;

    EnumerableSet.AddressSet internal pricingGroup;
    EnumerableSet.AddressSet internal clustersGroup;
    EnumerableSet.AddressSet internal endpointGroup;

    /// USER HELPERS ///

    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        return user;
    }

    function createUserWithPrivKey(string memory name) internal returns (uint256 privKey, address payable) {
        privKey = uint256(uint160(makeAddr("SIGNER")));
        address payable user = payable(vm.addr(privKey));
        vm.label({account: user, newLabel: name});
        vm.deal(user, constants.USERS_FUNDING_AMOUNT());
        return (privKey, user);
    }

    function createAndFundUser(string memory name, uint256 ethAmount) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: ethAmount});
        return user;
    }

    /// SETUP ///

    function setUp() public virtual {
        eid1 = new EndpointV2Mock(1);
        eid2 = new EndpointV2Mock(2);

        constants = new Constants();
        uint256 fundingAmount = constants.USERS_FUNDING_AMOUNT();
        fickleReceiver = new FickleReceiver();
        vm.deal(address(fickleReceiver), fundingAmount);

        users = Users({
            signerPrivKey: 0,
            signer: payable(address(0)),
            clustersAdmin: createUser("Clusters Admin"),
            alicePrimary: createAndFundUser("Alice (Primary)", fundingAmount),
            aliceSecondary: createAndFundUser("Alice (Secondary)", fundingAmount),
            bobPrimary: createAndFundUser("Bob (Primary)", fundingAmount),
            bobSecondary: createAndFundUser("Bob (Secondary)", fundingAmount),
            bidder: createAndFundUser("Bidder", fundingAmount),
            hacker: createAndFundUser("Malicious User", fundingAmount)
        });
        (users.signerPrivKey, users.signer) = createUserWithPrivKey("Signer");

        vm.warp(constants.START_TIME());

        pricingFlat = new PricingFlat();
        pricingHarberger = new PricingHarbergerHarness();
        endpoint = new Endpoint();

        vm.label(address(eid1), "EndpointV2Mock EID: 1");
        vm.label(address(eid2), "EndpointV2Mock EID: 2");
        vm.label(address(pricingFlat), "PricingFlat Implementation");
        vm.label(address(pricingHarberger), "PricingHarberger Implementation");
        vm.label(address(endpoint), "Endpoint Implementation");
    }

    function configureFlatEnvironment() internal {
        deployHubFlat(address(eid1));
        deploySpokeFlat(address(eid2));
        eid1.setDestLzEndpoint(endpointGroup.at(1), address(eid2));
        eid2.setDestLzEndpoint(endpointGroup.at(0), address(eid1));
        vm.startPrank(users.clustersAdmin);
        Endpoint(endpointGroup.at(0)).setPeer(2, _addressToBytes32(endpointGroup.at(1)));
        Endpoint(endpointGroup.at(1)).setPeer(1, _addressToBytes32(endpointGroup.at(0)));
        Endpoint(endpointGroup.at(1)).setDstEid(1);
        vm.stopPrank();
    }

    function configureHarbergerEnvironment() internal {
        deployHubHarberger(address(eid1));
        deploySpokeHarberger(address(eid2));
        eid1.setDestLzEndpoint(endpointGroup.at(1), address(eid2));
        eid2.setDestLzEndpoint(endpointGroup.at(0), address(eid1));
        vm.startPrank(users.clustersAdmin);
        Endpoint(endpointGroup.at(0)).setPeer(2, _addressToBytes32(endpointGroup.at(1)));
        Endpoint(endpointGroup.at(1)).setPeer(1, _addressToBytes32(endpointGroup.at(0)));
        Endpoint(endpointGroup.at(1)).setDstEid(1);
        vm.stopPrank();
    }

    /// DEPLOY ///

    function deployHubFlat(address lzEndpoint)
        internal
        returns (address clustersAddr, address endpointAddr, address pricingAddr)
    {
        pricingProxy = IPricing(LibClone.deployERC1967(address(pricingFlat)));
        PricingFlat(address(pricingProxy)).initialize(users.clustersAdmin);
        minPrice = pricingProxy.minAnnualPrice();

        endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        Endpoint(address(endpointProxy)).initialize(users.clustersAdmin, users.signer, lzEndpoint);
        clusters = new ClustersHub(address(pricingProxy), address(endpointProxy), constants.MARKET_OPEN_TIMESTAMP());

        vm.label(address(pricingProxy), "PricingFlat Hub EID-1");
        vm.label(address(clusters), "Clusters Hub EID-1");
        vm.label(address(endpointProxy), "Endpoint Hub EID-1");

        vm.prank(users.clustersAdmin);
        endpointProxy.setClustersAddr(address(clusters));

        pricingGroup.add(address(pricingProxy));
        clustersGroup.add(address(clusters));
        endpointGroup.add(address(endpointProxy));
        return (address(clusters), address(endpointProxy), address(pricingProxy));
    }

    function deploySpokeFlat(address lzEndpoint)
        internal
        returns (address clustersAddr, address endpointAddr, address pricingAddr)
    {
        pricingProxy = IPricing(LibClone.deployERC1967(address(pricingFlat)));
        PricingFlat(address(pricingProxy)).initialize(users.clustersAdmin);
        minPrice = pricingProxy.minAnnualPrice();

        endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        Endpoint(address(endpointProxy)).initialize(users.clustersAdmin, users.signer, lzEndpoint);
        //clusters = new ClustersHub(address(pricingProxy), address(endpointProxy), constants.MARKET_OPEN_TIMESTAMP());

        //vm.prank(users.clustersAdmin);
        //endpointProxy.setClustersAddr(address(clusters));

        pricingGroup.add(address(pricingProxy));
        clustersGroup.add(address(0));
        endpointGroup.add(address(endpointProxy));

        vm.label(address(pricingProxy), LibString.concat("PricingFlat Spoke EID-", pricingGroup.length().toString()));
        //vm.label(address(clusters), LibString.concat("Clusters Spoke EID-", clustersGroup.length().toString()));
        vm.label(address(endpointProxy), LibString.concat("Endpoint Spoke EID-", endpointGroup.length().toString()));

        return (address(0), address(endpointProxy), address(pricingProxy));
    }

    function deployHubHarberger(address lzEndpoint)
        internal
        returns (address clustersAddr, address endpointAddr, address pricingAddr)
    {
        pricingProxy = IPricing(LibClone.deployERC1967(address(pricingHarberger)));
        PricingHarbergerHarness(address(pricingProxy)).initialize(users.clustersAdmin, block.timestamp);
        minPrice = pricingProxy.minAnnualPrice();

        endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        Endpoint(address(endpointProxy)).initialize(users.clustersAdmin, users.signer, lzEndpoint);
        clusters = new ClustersHub(address(pricingProxy), address(endpointProxy), constants.MARKET_OPEN_TIMESTAMP());

        vm.label(address(pricingProxy), "PricingHarberger Hub EID-1");
        vm.label(address(clusters), "Clusters Hub EID-1");
        vm.label(address(endpointProxy), "Endpoint Hub EID-1");

        vm.prank(users.clustersAdmin);
        endpointProxy.setClustersAddr(address(clusters));

        pricingGroup.add(address(pricingProxy));
        clustersGroup.add(address(clusters));
        endpointGroup.add(address(endpointProxy));
        return (address(clusters), address(endpointProxy), address(pricingProxy));
    }

    function deploySpokeHarberger(address lzEndpoint)
        internal
        returns (address clustersAddr, address endpointAddr, address pricingAddr)
    {
        pricingProxy = IPricing(LibClone.deployERC1967(address(pricingHarberger)));
        PricingHarbergerHarness(address(pricingProxy)).initialize(users.clustersAdmin, block.timestamp);
        minPrice = pricingProxy.minAnnualPrice();

        endpointProxy = IEndpoint(LibClone.deployERC1967(address(endpoint)));
        Endpoint(address(endpointProxy)).initialize(users.clustersAdmin, users.signer, lzEndpoint);
        //clusters = new ClustersHub(address(pricingProxy), address(endpointProxy), constants.MARKET_OPEN_TIMESTAMP());

        //vm.prank(users.clustersAdmin);
        //endpointProxy.setClustersAddr(address(clusters));

        pricingGroup.add(address(pricingProxy));
        clustersGroup.add(address(0));
        endpointGroup.add(address(endpointProxy));

        vm.label(
            address(pricingProxy), LibString.concat("PricingHarberger Spoke EID-", pricingGroup.length().toString())
        );
        //vm.label(address(clusters), LibString.concat("Clusters Spoke EID-", clustersGroup.length().toString()));
        vm.label(address(endpointProxy), LibString.concat("Endpoint Spoke EID-", endpointGroup.length().toString()));

        return (address(0), address(endpointProxy), address(pricingProxy));
    }

    /// ASSERT HELPERS ///

    function assertBalances(
        uint256 totalBal,
        uint256 protocolAccrual,
        uint256 totalNameBacking,
        uint256 totalBidBacking
    ) internal {
        assertEq(address(clusters).balance, totalBal, "clusters total balance error");
        assertEq(clusters.protocolAccrual(), protocolAccrual, "clusters protocol accrual error");
        assertEq(clusters.totalNameBacking(), totalNameBacking, "clusters total name backing error");
        assertEq(clusters.totalBidBacking(), totalBidBacking, "clusters total bid backing error");
        assertEq(totalBal, protocolAccrual + totalNameBacking + totalBidBacking, "clusters balance invariant error");
    }

    function assertBalances(
        uint32 eid,
        uint256 totalBal,
        uint256 protocolAccrual,
        uint256 totalNameBacking,
        uint256 totalBidBacking
    ) internal {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);
        assertEq(address(eidClusters).balance, totalBal, "clusters total balance error");
        assertEq(ClustersHub(eidClusters).protocolAccrual(), protocolAccrual, "clusters protocol accrual error");
        assertEq(ClustersHub(eidClusters).totalNameBacking(), totalNameBacking, "clusters total name backing error");
        assertEq(ClustersHub(eidClusters).totalBidBacking(), totalBidBacking, "clusters total bid backing error");
        assertEq(totalBal, protocolAccrual + totalNameBacking + totalBidBacking, "clusters balance invariant error");
    }

    function assertUnverifiedAddresses(uint256 clusterId, uint256 count, bytes32[] memory containsAddrs) internal {
        bytes32[] memory unverified = clusters.getUnverifiedAddresses(clusterId);
        if (unverified.length > 0) {
            for (uint256 i; i < unverified.length; ++i) {
                values[clusterId].add(unverified[i]);
            }
        }
        assertEq(unverified.length, count, "unverified addresses array length error");
        for (uint256 i; i < containsAddrs.length; ++i) {
            assertEq(
                values[clusterId].contains(containsAddrs[i]), true, "clusterId does not contain unverified address"
            );
            assertEq(0, clusters.addressToClusterId(containsAddrs[i]), "address incorrectly assigned to clusterId");
        }
    }

    function assertUnverifiedAddresses(uint32 eid, uint256 clusterId, uint256 count, bytes32[] memory containsAddrs)
        internal
    {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        bytes32[] memory unverified = ClustersHub(eidClusters).getUnverifiedAddresses(clusterId);
        if (unverified.length > 0) {
            for (uint256 i; i < unverified.length; ++i) {
                values[clusterId].add(unverified[i]);
            }
        }
        assertEq(unverified.length, count, "unverified addresses array length error");
        for (uint256 i; i < containsAddrs.length; ++i) {
            assertEq(
                values[clusterId].contains(containsAddrs[i]), true, "clusterId does not contain unverified address"
            );
            assertEq(
                0,
                ClustersHub(eidClusters).addressToClusterId(containsAddrs[i]),
                "address incorrectly assigned to clusterId"
            );
        }
    }

    function assertVerifiedAddresses(uint256 clusterId, uint256 count, bytes32[] memory containsAddrs) internal {
        bytes32[] memory verified = clusters.getVerifiedAddresses(clusterId);
        if (verified.length > 0) {
            for (uint256 i; i < verified.length; ++i) {
                values[clusterId].add(verified[i]);
            }
        }
        assertEq(verified.length, count, "verified addresses array length error");
        for (uint256 i; i < containsAddrs.length; ++i) {
            assertEq(values[clusterId].contains(containsAddrs[i]), true, "clusterId does not contain verified address");
            assertEq(clusterId, clusters.addressToClusterId(containsAddrs[i]), "address not assigned to clusterId");
        }
    }

    function assertVerifiedAddresses(uint32 eid, uint256 clusterId, uint256 count, bytes32[] memory containsAddrs)
        internal
    {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        bytes32[] memory verified = ClustersHub(eidClusters).getVerifiedAddresses(clusterId);
        if (verified.length > 0) {
            for (uint256 i; i < verified.length; ++i) {
                values[clusterId].add(verified[i]);
            }
        }
        assertEq(verified.length, count, "verified addresses array length error");
        for (uint256 i; i < containsAddrs.length; ++i) {
            assertEq(values[clusterId].contains(containsAddrs[i]), true, "clusterId does not contain verified address");
            assertEq(
                clusterId,
                ClustersHub(eidClusters).addressToClusterId(containsAddrs[i]),
                "address not assigned to clusterId"
            );
        }
    }

    function assertClusterNames(uint256 clusterId, uint256 count, bytes32[] memory containsNames) internal {
        bytes32[] memory names = clusters.getClusterNamesBytes32(clusterId);
        if (names.length > 0) {
            for (uint256 i; i < names.length; ++i) {
                values[clusterId].add(names[i]);
            }
        }
        assertEq(names.length, count, "cluster names array length error");
        for (uint256 i; i < containsNames.length; ++i) {
            assertEq(values[clusterId].contains(containsNames[i]), true, "clusterId does not contain name");
            assertEq(clusterId, clusters.nameToClusterId(containsNames[i]), "name not assigned to clusterId");
        }
    }

    function assertClusterNames(uint32 eid, uint256 clusterId, uint256 count, bytes32[] memory containsNames)
        internal
    {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        bytes32[] memory names = ClustersHub(eidClusters).getClusterNamesBytes32(clusterId);
        if (names.length > 0) {
            for (uint256 i; i < names.length; ++i) {
                values[clusterId].add(names[i]);
            }
        }
        assertEq(names.length, count, "cluster names array length error");
        for (uint256 i; i < containsNames.length; ++i) {
            assertEq(values[clusterId].contains(containsNames[i]), true, "clusterId does not contain name");
            assertEq(
                clusterId, ClustersHub(eidClusters).nameToClusterId(containsNames[i]), "name not assigned to clusterId"
            );
        }
    }

    function assertWalletName(uint256 clusterId, bytes32 addr, string memory name) internal {
        assertEq(addr, clusters.forwardLookup(clusterId, _stringToBytes32(name)), "forwardLookup error");
        assertEq(_stringToBytes32(name), clusters.reverseLookup(addr));
    }

    function assertWalletName(uint32 eid, uint256 clusterId, bytes32 addr, string memory name) internal {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        assertEq(addr, ClustersHub(eidClusters).forwardLookup(clusterId, _stringToBytes32(name)), "forwardLookup error");
        assertEq(_stringToBytes32(name), ClustersHub(eidClusters).reverseLookup(addr));
    }

    function assertNameBacking(string memory name, uint256 nameBacking) internal {
        assertEq(nameBacking, clusters.nameBacking(_stringToBytes32(name)), "name backing incorrect");
    }

    function assertNameBacking(uint32 eid, string memory name, uint256 nameBacking) internal {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        assertEq(nameBacking, ClustersHub(eidClusters).nameBacking(_stringToBytes32(name)), "name backing incorrect");
    }

    function assertBid(string memory name, uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder) internal {
        (uint256 _ethAmount, uint256 _createdTimestamp, bytes32 _bidder) = clusters.bids(_stringToBytes32(name));
        assertEq(ethAmount, _ethAmount, "bid ethAmount error");
        assertEq(createdTimestamp, _createdTimestamp, "bid createdTimestamp error");
        assertEq(bidder, _bidder, "bid bidder error");
    }

    function assertBid(uint32 eid, string memory name, uint256 ethAmount, uint256 createdTimestamp, bytes32 bidder)
        internal
    {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidClusters = clustersGroup.at(eid - 1);

        (uint256 _ethAmount, uint256 _createdTimestamp, bytes32 _bidder) =
            ClustersHub(eidClusters).bids(_stringToBytes32(name));
        assertEq(ethAmount, _ethAmount, "bid ethAmount error");
        assertEq(createdTimestamp, _createdTimestamp, "bid createdTimestamp error");
        assertEq(bidder, _bidder, "bid bidder error");
    }

    function assertEndpointVars(address clusters_, address signer) internal {
        assertEq(clusters_, endpointProxy.clusters(), "endpoint clusters address error");
        assertEq(signer, endpointProxy.signer(), "endpoint signer address error");
    }

    function assertEndpointVars(uint32 eid, address clusters_, address signer) internal {
        assertFalse(eid < 1, "EID cannot be 0");
        address eidEndpoint = endpointGroup.at(eid - 1);

        assertEq(clusters_, Endpoint(eidEndpoint).clusters(), "endpoint clusters address error");
        assertEq(signer, Endpoint(eidEndpoint).signer(), "endpoint signer address error");
    }
}
