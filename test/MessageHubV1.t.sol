// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./utils/SoladyTest.sol";
import "./mocks/MockMessageHubV1.sol";
import "clusters/MessageInitiatorV1.sol";
import "devtools/mocks/EndpointV2Mock.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract Target {
    address public hub;
    uint256 public x;
    uint256 public msgValueDuringSetX;
    address public msgSenderDuringSetX;
    address public senderDuringSetX;
    bytes32 public originalSenderDuringSetX;
    uint256 public originalSenderTypeDuringSetX;
    uint256 public refundAmount;

    function depositRefund() public payable {
        refundAmount += msg.value;
    }

    function setHub(address newHub) public {
        hub = newHub;
    }

    function setX(uint256 newX) public payable {
        msgValueDuringSetX = msg.value;
        msgSenderDuringSetX = msg.sender;
        x = newX;
        (bool success, bytes memory results) = hub.staticcall("");
        (senderDuringSetX, originalSenderDuringSetX, originalSenderTypeDuringSetX) =
            abi.decode(results, (address, bytes32, uint256));
        require(success);

        (success,) = msg.sender.call{value: refundAmount}("");
        require(success);
        refundAmount = 0;
    }
}

contract MessagehubV1Test is SoladyTest {
    MockMessageHubV1 hub;
    MessageInitiatorV1 initiator;

    EndpointV2Mock eid1;
    EndpointV2Mock eid2;

    Target target;

    address constant ALICE = address(111);

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function setUp() public {
        eid1 = new EndpointV2Mock(1);
        eid2 = new EndpointV2Mock(2);

        hub = MockMessageHubV1(payable(LibClone.deployERC1967(address(new MockMessageHubV1()))));
        hub.initialize(address(eid1), address(this));
        assertEq(hub.owner(), address(this));

        initiator = MessageInitiatorV1(payable(LibClone.deployERC1967(address(new MessageInitiatorV1()))));
        initiator.initialize(address(eid2), address(this));
        assertEq(initiator.owner(), address(this));

        initiator.setPeer(1, bytes32(uint256(uint160(address(hub)))));
        hub.setPeer(2, bytes32(uint256(uint160(address(initiator)))));

        initiator.setDstEid(1);

        eid1.setDestLzEndpoint(address(initiator), address(eid2));
        eid2.setDestLzEndpoint(address(hub), address(eid1));

        target = new Target();
        target.setHub(address(hub));
    }

    function testSubAccountArgsDifferential(bytes32 originalSender, uint256 originalSenderType) public view {
        bytes memory expected =
            abi.encodePacked(keccak256(abi.encode(originalSender, originalSenderType)), address(hub));
        assertEq(hub.subAccountArgs(originalSender, originalSenderType), expected);
    }

    function testCrosschain() public {
        uint256 gas = 1000000;
        uint256 value = 1 ether;
        uint256 newX = _random();

        bytes memory data = abi.encodeWithSignature("setX(uint256)", newX);

        uint256 nativeFee = initiator.quoteWithDefaultOptions(address(target), data, gas, value);

        vm.deal(ALICE, 10 ether);

        vm.prank(ALICE);
        initiator.sendWithDefaultOptions{value: nativeFee}(address(target), data, gas, value);

        assertEq(target.x(), newX);
        assertEq(target.msgValueDuringSetX(), 1 ether);
        assertEq(target.msgSenderDuringSetX(), address(hub));

        assertEq(target.originalSenderDuringSetX(), bytes32(uint256(uint160(ALICE))));
        assertEq(target.originalSenderTypeDuringSetX(), 0);
        assertEq(target.senderDuringSetX(), ALICE);
    }

    struct _TestMothershipTemps {
        bool originalSenderIsEthereumAddress;
        bytes32 originalSender;
        uint256 originalSenderType;
        address sender;
        bytes message;
        uint256 newX;
        uint256 refundAmount;
    }

    function testMothership(bytes32) public {
        _TestMothershipTemps memory t;

        t.originalSenderIsEthereumAddress = _randomChance(2);

        if (t.originalSenderIsEthereumAddress) {
            t.sender = _randomNonZeroAddress();
            t.originalSenderType = 0;
            t.originalSender = bytes32(uint256(uint160(t.sender)));
        } else {
            t.originalSender = bytes32(_random());
            t.originalSenderType = 1 | _random();
            while (t.originalSender == bytes32(0)) t.originalSender = bytes32(_random());
            t.sender = hub.predictSubAccount(t.originalSender, t.originalSenderType);
            assertEq(hub.createSubAccount(t.originalSender, t.originalSenderType), t.sender);
        }
        t.newX = _random();

        vm.deal(address(this), 10 ether);
        vm.deal(address(hub), _random() % 0.1 ether);

        t.message = abi.encode(
            t.originalSender, t.originalSenderType, address(target), abi.encodeWithSignature("setX(uint256)", t.newX)
        );

        vm.deal(address(this), 10 ether);
        t.refundAmount = _random() % 1 ether;
        target.depositRefund{value: t.refundAmount}();

        hub.forward{value: 1 ether}(t.message);

        assertEq(target.msgValueDuringSetX(), 1 ether);
        assertEq(target.msgSenderDuringSetX(), address(hub));
        assertEq(target.originalSenderDuringSetX(), t.originalSender);
        assertEq(target.originalSenderTypeDuringSetX(), t.originalSenderType);
        assertEq(target.senderDuringSetX(), t.sender);

        assertEq(target.x(), t.newX);
        assertEq(t.sender.balance, t.refundAmount);
    }
}
