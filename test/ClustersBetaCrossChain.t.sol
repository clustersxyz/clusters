// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//import "layerzero-oapp/test/TestHelper.sol";
import "devtools/mocks/EndpointV2Mock.sol";
import "forge-std/Test.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
import {OAppUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppUpgradeable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Utils} from "./utils/Utils.sol";

import {ClustersBeta} from "clusters/ClustersBeta.sol";
import {InitiatorBeta} from "clusters/InitiatorBeta.sol";

import {Constants} from "./utils/Constants.sol";
import {Users} from "./utils/Types.sol";
import {console2} from "forge-std/Test.sol";

import {Endpoint} from "./Base.t.sol";

contract ClustersBetaCrossChainTest is Test, Utils {
    using OptionsBuilder for bytes;

    /// VARIABLES ///

    Users internal users;
    uint256 internal minPrice;
    Constants internal constants;

    /// CONTRACTS ///

    EndpointV2Mock internal eid1;
    EndpointV2Mock internal eid2;

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

    function setUp() public virtual {
        eid1 = new EndpointV2Mock(1);
        eid2 = new EndpointV2Mock(2);

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

        // Deploy and initialize contracts
        vm.startPrank(users.clustersAdmin);
        clustersImplementation = new ClustersBeta();
        initiatorImplementation = new InitiatorBeta();
        clustersProxy = ClustersBeta(LibClone.deployERC1967(address(clustersImplementation)));
        clustersProxy.initialize(address(eid1), users.clustersAdmin);
        initiatorProxy = InitiatorBeta(LibClone.deployERC1967(address(initiatorImplementation)));
        initiatorProxy.initialize(address(eid2), users.clustersAdmin);
        initiatorProxy.setPeer(1, _addressToBytes32(address(clustersProxy)));
        clustersProxy.setPeer(2, _addressToBytes32(address(initiatorProxy)));
        initiatorProxy.setDstEid(1);
        eid1.setDestLzEndpoint(address(initiatorProxy), address(eid2));
        eid2.setDestLzEndpoint(address(clustersProxy), address(eid1));

        // Label deployed contracts
        vm.label(address(eid1), "EndpointV2Mock EID: 1");
        vm.label(address(eid2), "EndpointV2Mock EID: 2");
        vm.label(address(clustersImplementation), "ClustersBeta Implementation");
        vm.label(address(clustersProxy), "ClustersBeta Proxy");
        vm.label(address(initiatorImplementation), "InitiatorBeta Implementation");
        vm.label(address(initiatorProxy), "InitiatorBeta Proxy");
        vm.stopPrank();
    }

    function testCrosschain() public {
        vm.startPrank(users.alicePrimary);
        clustersProxy.placeBid{value: 0.1 ether}("foobar");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;
        bytes32[] memory names = new bytes32[](2);
        names[0] = "foobar2";
        names[1] = "foobar3";
        clustersProxy.placeBids{value: 0.2 ether}(amounts, names);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(199_000, 0.1 ether);
        bytes memory message = abi.encodeWithSignature("placeBid(bytes32)", bytes32("foobarCrosschain"));
        bytes32 from = bytes32(uint256(uint160(address(users.alicePrimary))));
        uint256 nativeFee = initiatorProxy.quote(abi.encode(from, message), options);
        initiatorProxy.lzSend{value: nativeFee}(message, options);

        vm.stopPrank();

        // vm.expectEmit(true, false, false, false, address(clustersProxy));
        // vm.expectEmit();
        //verifyPackets(1, address(clustersProxy));
        emit ClustersBeta.Bid(from, 0.1 ether, bytes32("foobarCrosschain"));
    }
}
