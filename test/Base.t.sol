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

abstract contract Base_Test is Test, Utils {
    /// VARIABLES ///

    Users internal users;

    /// TEST CONTRACTS ///

    Constants internal constants;
    PricingFlat internal pricingFlat;
    PricingHarbergerHarness internal pricingHarberger;
    IEndpoint internal endpoint;
    IClusters internal clusters;
    FickleReceiver internal fickleReceiver;

    /// HELPER FUNCTIONS ///

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
    }

    /// DEPLOY ///

    function deployLocalFlat() internal {
        pricingFlat = new PricingFlat();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricingFlat), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
    }

    function deployLocalHarberger() internal {
        pricingHarberger = new PricingHarbergerHarness();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricingHarberger), address(endpoint), constants.MARKET_OPEN_TIMESTAMP());
    }
}
