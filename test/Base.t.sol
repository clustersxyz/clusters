// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../lib/LayerZero-v2/oapp/test/TestHelper.sol";
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
import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {console2} from "forge-std/Test.sol";

abstract contract Base_Test is TestHelper, Utils {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// VARIABLES ///

    Users internal users;
    uint256 internal minPrice;
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set vals) internal values;

    /// TEST CONTRACTS ///

    Constants internal constants;
    PricingFlat internal pricingFlat;
    PricingHarbergerHarness internal pricingHarberger;
    IEndpoint internal endpoint;
    IClustersHub internal clusters;
    FickleReceiver internal fickleReceiver;

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

    function setUp() public virtual override {
        super.setUp();
        constants = new Constants();
        uint256 fundingAmount = constants.USERS_FUNDING_AMOUNT();
        fickleReceiver = new FickleReceiver();
        vm.deal(address(fickleReceiver), fundingAmount);

        users = Users({
            signerPrivKey: 0,
            signer: payable(address(0)),
            endpointAdmin: createUser("Endpoint Admin"),
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
        pricingHarberger = new PricingHarbergerHarness(block.timestamp);
    }

    function configureFlatEnvironment(uint8 instances) internal {
        setUpEndpoints(instances, LibraryType.UltraLightNode);
        for (uint8 i; i < instances; ++i) {
            if (i == 0) {
                deployHubFlat(endpoints[1]);
            } else {
                deploySpokeFlat(endpoints[i + 1]);
            }
        }
        vm.startPrank(users.endpointAdmin);
        wireOApps(endpointGroup.values());
        vm.stopPrank();
    }

    function configureHarbergerEnvironment(uint8 instances) internal {
        setUpEndpoints(instances, LibraryType.UltraLightNode);
        for (uint8 i; i < instances; ++i) {
            if (i == 0) {
                deployHubHarberger(endpoints[1]);
            } else {
                deploySpokeHarberger(endpoints[i + 1]);
            }
        }
        vm.startPrank(users.endpointAdmin);
        wireOApps(endpointGroup.values());
        vm.stopPrank();
    }

    /// DEPLOY ///

    function deployHubFlat(address lzEndpoint) internal returns (address clustersAddr, address endpointAddr) {
        minPrice = pricingFlat.minAnnualPrice();
        endpoint = new Endpoint(users.endpointAdmin, users.signer, lzEndpoint);
        clusters = new ClustersHub(address(pricingFlat), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        vm.prank(users.endpointAdmin);
        endpoint.setClustersAddr(address(clusters));
        clustersGroup.add(address(clusters));
        endpointGroup.add(address(endpoint));
        return (address(clusters), address(endpoint));
    }

    function deploySpokeFlat(address lzEndpoint) internal returns (address clustersAddr, address endpointAddr) {
        minPrice = pricingFlat.minAnnualPrice();
        endpoint = new Endpoint(users.endpointAdmin, users.signer, lzEndpoint);
        //clusters = new ClustersHub(address(pricingFlat), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        //vm.prank(users.endpointAdmin);
        //endpoint.setClustersAddr(address(clusters));
        clustersGroup.add(address(0));
        endpointGroup.add(address(endpoint));
        return (address(0), address(endpoint));
    }

    function deployHubHarberger(address lzEndpoint) internal returns (address clustersAddr, address endpointAddr) {
        minPrice = pricingHarberger.minAnnualPrice();
        endpoint = new Endpoint(users.endpointAdmin, users.signer, lzEndpoint);
        clusters = new ClustersHub(address(pricingHarberger), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        vm.prank(users.endpointAdmin);
        endpoint.setClustersAddr(address(clusters));
        clustersGroup.add(address(clusters));
        endpointGroup.add(address(endpoint));
        return (address(clusters), address(endpoint));
    }

    function deploySpokeHarberger(address lzEndpoint) internal returns (address clustersAddr, address endpointAddr) {
        minPrice = pricingHarberger.minAnnualPrice();
        endpoint = new Endpoint(users.endpointAdmin, users.signer, lzEndpoint);
        //clusters = new ClustersHub(address(pricingHarberger), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        //vm.prank(users.endpointAdmin);
        //endpoint.setClustersAddr(address(clusters));
        clustersGroup.add(address(0));
        endpointGroup.add(address(endpoint));
        return (address(0), address(endpoint));
    }

    /// ASSERT HELPERS ///

    function assertBalances(
        uint256 totalBal,
        uint256 protocolAccrual,
        uint256 totalNameBacking,
        uint256 totalBidBacking
    ) internal {
        assertEq(address(endpoint).balance, 0, "endpoint has balance");
        assertEq(address(clusters).balance, totalBal, "clusters total balance error");
        assertEq(clusters.protocolAccrual(), protocolAccrual, "clusters protocol accrual error");
        assertEq(clusters.totalNameBacking(), totalNameBacking, "clusters total name backing error");
        assertEq(clusters.totalBidBacking(), totalBidBacking, "clusters total bid backing error");
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

    function assertWalletName(uint256 clusterId, bytes32 addr, string memory name) internal {
        assertEq(addr, clusters.forwardLookup(clusterId, _stringToBytes32(name)), "forwardLookup error");
        assertEq(_stringToBytes32(name), clusters.reverseLookup(addr));
    }

    function assertNameBacking(string memory name, uint256 nameBacking) internal {
        assertEq(nameBacking, clusters.nameBacking(_stringToBytes32(name)), "name backing incorrect");
    }

    function assertEndpointVars(address clusters_, address signer) internal {
        assertEq(clusters_, endpoint.clusters(), "endpoint clusters address error");
        assertEq(signer, endpoint.signer(), "endpoint signer address error");
    }
}
