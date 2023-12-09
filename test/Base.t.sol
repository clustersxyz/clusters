// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";

import {IPricing} from "../src/interfaces/IPricing.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {IClusters} from "../src/interfaces/IClusters.sol";

import {PricingFlat} from "../src/PricingFlat.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {Clusters} from "../src/Clusters.sol";

import {FickleReceiver} from "./mocks/FickleReceiver.sol";
import {Defaults} from "./utils/Defaults.sol";
import {Users} from "./utils/Types.sol";

abstract contract Base_Test is Test, Utils {
    /// VARIABLES ///

    Users internal users;

    /// TEST CONTRACTS ///

    Defaults internal defaults;
    IPricing internal pricing;
    IEndpoint internal endpoint;
    IClusters internal clusters;
    FickleReceiver internal fickleReceiver;

    /// HELPER FUNCTIONS ///

    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.label({account: user, newLabel: name});
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
        vm.label({account: user, newLabel: name});
        vm.deal({account: user, newBalance: ethAmount});
        return user;
    }

    /// SETUP ///

    function setUp() public virtual {
        fickleReceiver = new FickleReceiver();

        users = Users({
            signerPrivKey: 0,
            signer: payable(address(0)),
            adminEndpoint: createUser("Endpoint Admin"),
            alicePrimary: createAndFundUser("Alice (Primary)", defaults.USERS_FUNDING_AMOUNT()),
            aliceSecondary: createAndFundUser("Alice (Secondary)", defaults.USERS_FUNDING_AMOUNT()),
            bobPrimary: createAndFundUser("Bob (Primary)", defaults.USERS_FUNDING_AMOUNT()),
            bobSecondary: createAndFundUser("Bob (Secondary)", defaults.USERS_FUNDING_AMOUNT()),
            bidder: createAndFundUser("Bidder", defaults.USERS_FUNDING_AMOUNT()),
            hacker: createAndFundUser("Malicious User", defaults.USERS_FUNDING_AMOUNT())
        });
        (users.signerPrivKey, users.signer) = createUserWithPrivKey("Signer");
    }

    /// DEPLOY ///

    function deployLocalFlat() internal {
        pricing = new PricingFlat();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricing), address(endpoint), defaults.MARKET_OPEN_TIMESTAMP());
    }

    function deployLocalHarberger() internal {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(users.adminEndpoint, users.signer);
        clusters = new Clusters(address(pricing), address(endpoint), defaults.MARKET_OPEN_TIMESTAMP());
    }
}
