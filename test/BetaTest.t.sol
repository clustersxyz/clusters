// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "layerzero-oapp/test/TestHelper.sol";
import {OAppUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppUpgradeable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Utils} from "./utils/Utils.sol";

import {ClustersBeta} from "clusters/ClustersBeta.sol";
import {InitiatorBeta} from "clusters/InitiatorBeta.sol";

import {Constants} from "./utils/Constants.sol";
import {Users} from "./utils/Types.sol";
import {console2} from "forge-std/Test.sol";

contract Beta_Test is TestHelper, Utils {
    /// VARIABLES ///

    Users internal users;
    uint256 internal minPrice;
    Constants internal constants;

    /// CONTRACTS ///

    ClustersBeta internal clustersImplementation;
    ClustersBeta internal clustersProxy;
    InitiatorBeta internal initiatorImplementation;
    InitiatorBeta internal initiatorProxy;

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

        // Set state variables
        constants = new Constants();
        vm.warp(constants.START_TIME());
        uint256 fundingAmount = constants.USERS_FUNDING_AMOUNT();
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

        // Configure local LayerZero environment
        setUpEndpoints(2, LibraryType.UltraLightNode);
        vm.label(endpoints[1], "L0 Endpoint EID-1");
        vm.label(endpoints[2], "L0 Endpoint EID-2");

        // Deploy and initialize contracts
        vm.startPrank(users.clustersAdmin);
        clustersImplementation = new ClustersBeta();
        initiatorImplementation = new InitiatorBeta();
        clustersProxy = ClustersBeta(LibClone.deployERC1967(address(clustersImplementation)));
        clustersProxy.initialize(endpoints[1], users.clustersAdmin);
        initiatorProxy = InitiatorBeta(LibClone.deployERC1967(address(initiatorImplementation)));
        initiatorProxy.initialize(endpoints[2], users.clustersAdmin);
        initiatorProxy.setDstEid(1);
        initiatorProxy.setPeer(1, _addressToBytes32(address(clustersProxy)));
        clustersProxy.setPeer(2, _addressToBytes32(address(initiatorProxy)));

        // Label deployed contracts
        vm.label(address(clustersImplementation), "ClustersBeta Implementation");
        vm.label(address(clustersProxy), "ClustersBeta Proxy");
        vm.label(address(initiatorImplementation), "InitiatorBeta Implementation");
        vm.label(address(initiatorProxy), "InitiatorBeta Proxy");
        vm.stopPrank();
    }

    function testSetup() public {}
}
