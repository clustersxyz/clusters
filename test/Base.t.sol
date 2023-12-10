// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";

import {IPricing} from "../src/interfaces/IPricing.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {IClusters} from "../src/interfaces/IClusters.sol";

import {PricingFlat} from "../src/PricingFlat.sol";
import {PricingHarbergerHarness} from "./harness/PricingHarbergerHarness.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

import {FickleReceiver} from "./mocks/FickleReceiver.sol";
import {Constants} from "./utils/Constants.sol";
import {Users} from "./utils/Types.sol";
import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

abstract contract Base_Test is Test, Utils {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// VARIABLES ///

    Users internal users;
    uint256 internal minPrice;
    mapping(uint256 clusterId => EnumerableSet.Bytes32Set addrs) internal values;

    /// TEST CONTRACTS ///

    Constants internal constants;
    PricingFlat internal pricingFlat;
    PricingHarbergerHarness internal pricingHarberger;
    IEndpoint internal endpoint;
    IClusters internal clusters;
    FickleReceiver internal fickleReceiver;

    /// USER HELPERS ///

    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        return user;
    }

    function createUserWithPrivKey(string memory name) internal returns (uint256 privKey, address payable) {
        privKey = uint256(uint160(makeAddr("SIGNER")));
        address payable user = payable(vm.addr(privKey));
        vm.label({account: user, newLabel: name});
        return (privKey, user);
    }

    function createAndFundUser(string memory name, uint256 ethAmount) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: ethAmount});
        return user;
    }

    /// SETUP ///

    function setUp() public virtual {
        constants = new Constants();
        fickleReceiver = new FickleReceiver();

        users = Users({
            signerPrivKey: 0,
            signer: payable(address(0)),
            adminEndpoint: createUser("Endpoint Admin"),
            alicePrimary: createAndFundUser("Alice (Primary)", constants.USERS_FUNDING_AMOUNT()),
            aliceSecondary: createAndFundUser("Alice (Secondary)", constants.USERS_FUNDING_AMOUNT()),
            bobPrimary: createAndFundUser("Bob (Primary)", constants.USERS_FUNDING_AMOUNT()),
            bobSecondary: createAndFundUser("Bob (Secondary)", constants.USERS_FUNDING_AMOUNT()),
            bidder: createAndFundUser("Bidder", constants.USERS_FUNDING_AMOUNT()),
            hacker: createAndFundUser("Malicious User", constants.USERS_FUNDING_AMOUNT())
        });
        (users.signerPrivKey, users.signer) = createUserWithPrivKey("Signer");

        vm.warp(constants.START_TIME());
    }

    /// DEPLOY ///

    function deployLocalFlat() internal {
        pricingFlat = new PricingFlat();
        minPrice = pricingFlat.minAnnualPrice();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricingFlat), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        vm.prank(users.adminEndpoint);
        endpoint.setClustersAddr(address(clusters));
    }

    function deployLocalHarberger() internal {
        pricingHarberger = new PricingHarbergerHarness();
        minPrice = pricingHarberger.minAnnualPrice();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricingHarberger), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
        vm.prank(users.adminEndpoint);
        endpoint.setClustersAddr(address(clusters));
    }

    /// ASSERT HELPERS ///

    function assertBalances(
        uint256 totalBal,
        uint256 protocolRevenue,
        uint256 totalNameBacking,
        uint256 totalBidBacking
    ) internal {
        assertEq(address(endpoint).balance, 0, "endpoint has balance");
        assertEq(address(clusters).balance, totalBal, "clusters total balance error");
        assertEq(clusters.protocolRevenue(), protocolRevenue, "clusters protocol revenue error");
        assertEq(clusters.totalNameBacking(), totalNameBacking, "clusters total name backing error");
        assertEq(clusters.totalBidBacking(), totalBidBacking, "clusters total bid backing error");
        assertEq(totalBal, protocolRevenue + totalNameBacking + totalBidBacking, "clusters balance invariant error");
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
        }
    }
}
