// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {ClustersBeta} from "../src/ClustersBeta.sol";
import {InitiatorBeta} from "../src/InitiatorBeta.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

contract DeployBetaTestnetScript is Script {
    using OptionsBuilder for bytes;

    uint256 base;
    string internal BASE_RPC = vm.envString("BASE_SEPOLIA_RPC_URL");
    uint256 eth;
    string internal ETH_RPC = vm.envString("ETH_SEPOLIA_RPC_URL");
    uint256 arb;
    string internal ARB_RPC = vm.envString("ARB_SEPOLIA_RPC_URL");
    uint256 avax;
    string internal AVAX_RPC = vm.envString("AVAX_FUJI_RPC_URL");
    uint256 bnb;
    string internal BNB_RPC = vm.envString("BNB_TESTNET_RPC_URL");
    uint256 op;
    string internal OP_RPC = vm.envString("OP_SEPOLIA_RPC_URL");
    uint256 polygon;
    string internal POLYGON_RPC = vm.envString("POLYGON_MUMBAI_RPC_URL");

    uint32 constant BASE_EID = 40245;
    uint32 constant ETH_EID = 40161;
    uint32 constant ARB_EID = 40231;
    uint32 constant AVAX_EID = 40106;
    uint32 constant BNB_EID = 40102;
    uint32 constant OP_EID = 40232;
    uint32 constant POLYGON_EID = 40109;

    ICreateX createx = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed); // Same on all chains
    address constant lzTestnetEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f; // Same on all chains
    address constant zodomo = 0xA779fC675Db318dab004Ab8D538CB320D0013F42;
    address constant deployment = 0xb2fB6c8e16c219D2F437375228f09D14a1E8cBD5;
    bytes hubInitCode = type(ClustersBeta).creationCode;
    bytes initiatorInitCode = type(InitiatorBeta).creationCode;
    bytes32 salt = bytes32(abi.encodePacked(msg.sender, hex"00", bytes11(uint88(42069))));

    function setUp() public {
        base = vm.createFork(BASE_RPC);
        eth = vm.createFork(ETH_RPC);
        arb = vm.createFork(ARB_RPC);
        avax = vm.createFork(AVAX_RPC);
        bnb = vm.createFork(BNB_RPC);
        op = vm.createFork(OP_RPC);
        polygon = vm.createFork(POLYGON_RPC);
    }

    function deployHub() external {
        vm.startBroadcast();
        address hub = createx.deployCreate3(salt, hubInitCode);
        ClustersBeta(hub).initialize(lzTestnetEndpoint, zodomo);
        vm.stopBroadcast();
        require(hub == deployment, "address doesn't match");
        console2.log(hub);
    }

    function deployInitiator() external {
        vm.startBroadcast();
        address initiator = createx.deployCreate3(salt, initiatorInitCode);
        InitiatorBeta(initiator).initialize(lzTestnetEndpoint, zodomo);
        vm.stopBroadcast();
        require(initiator == deployment, "address doesn't match");
        console2.log(initiator);
    }

    function configureHub() external {
        vm.startBroadcast();
        ClustersBeta(deployment).setPeer(ETH_EID, bytes32(uint256(uint160(deployment))));
        ClustersBeta(deployment).setPeer(ARB_EID, bytes32(uint256(uint160(deployment))));
        ClustersBeta(deployment).setPeer(AVAX_EID, bytes32(uint256(uint160(deployment))));
        ClustersBeta(deployment).setPeer(BNB_EID, bytes32(uint256(uint160(deployment))));
        ClustersBeta(deployment).setPeer(OP_EID, bytes32(uint256(uint160(deployment))));
        ClustersBeta(deployment).setPeer(POLYGON_EID, bytes32(uint256(uint160(deployment))));
        vm.stopBroadcast();
    }

    function configureInitiator() external {
        vm.startBroadcast();
        InitiatorBeta(deployment).setPeer(BASE_EID, bytes32(uint256(uint160(deployment))));
        InitiatorBeta(deployment).setDstEid(BASE_EID);
        vm.stopBroadcast();
    }

    function doInitiate() external {
        uint256 amount = 0.01 ether;
        bytes32[] memory names = new bytes32[](7);
        names[0] = bytes32(bytes("zodomo1"));
        names[1] = bytes32(bytes("zodomo2"));
        names[2] = bytes32(bytes("zodomo3"));
        names[3] = bytes32(bytes("zodomo4"));
        names[4] = bytes32(bytes("zodomo5"));
        names[5] = bytes32(bytes("zodomo6"));
        names[6] = bytes32(bytes("zodomo7"));

        ClustersBeta hub = ClustersBeta(deployment);
        InitiatorBeta initiator = InitiatorBeta(deployment);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50_000, 0.01 ether);
        uint256 nativeFee;
        bytes[] memory messages = new bytes[](6);
        messages[0] = abi.encodeWithSignature("placeBid(bytes32)", names[1]);
        messages[1] = abi.encodeWithSignature("placeBid(bytes32)", names[2]);
        messages[2] = abi.encodeWithSignature("placeBid(bytes32)", names[3]);
        messages[3] = abi.encodeWithSignature("placeBid(bytes32)", names[4]);
        messages[4] = abi.encodeWithSignature("placeBid(bytes32)", names[5]);
        messages[5] = abi.encodeWithSignature("placeBid(bytes32)", names[6]);

        vm.selectFork(base);
        vm.startBroadcast(deployerPrivateKey);
        hub.placeBid{value: 0.01 ether}(names[0]);
        vm.stopBroadcast();

        vm.selectFork(eth);
        vm.startBroadcast(deployerPrivateKey);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[0]), options);
        initiator.lzSend{value: nativeFee}(messages[0], options);
        vm.stopBroadcast();

        vm.selectFork(arb);
        vm.startBroadcast(deployerPrivateKey);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[1]), options);
        initiator.lzSend{value: nativeFee}(messages[1], options);
        vm.stopBroadcast();

        vm.selectFork(avax);
        vm.startBroadcast(deployerPrivateKey);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[2]), options);
        initiator.lzSend{value: nativeFee}(messages[2], options);
        vm.stopBroadcast();

        vm.selectFork(bnb);
        vm.startBroadcast(deployerPrivateKey);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[3]), options);
        initiator.lzSend{value: nativeFee}(messages[3], options);
        vm.stopBroadcast();

        vm.selectFork(op);
        vm.startBroadcast(deployerPrivateKey);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[4]), options);
        initiator.lzSend{value: nativeFee}(messages[4], options);
        vm.stopBroadcast();

        vm.selectFork(polygon);
        vm.startBroadcast(deployerPrivateKey);
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50_000, 0.0001 ether);
        nativeFee = initiator.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), messages[5]), options);
        initiator.lzSend{value: nativeFee}(messages[5], options);
        vm.stopBroadcast();
    }
}
