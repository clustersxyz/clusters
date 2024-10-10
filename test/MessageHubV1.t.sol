// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./utils/SoladyTest.sol";
import "./mocks/MockMessageHubV1.sol";
import "clusters/MessageInitiatorV1.sol";
import "devtools/mocks/EndpointV2Mock.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract MessagehubV1Test is SoladyTest {
    MockMessageHubV1 hub;
    MessageInitiatorV1 initiator;

    EndpointV2Mock eid1;
    EndpointV2Mock eid2;

    uint256 x;
    uint256 valueDuringSetX;

    address constant ALICE = address(111);

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
    }

    function testCrosschain() public {
        uint256 gas = 100000;
        uint256 value = 1 ether;
        uint256 newX = _random();

        bytes memory data = abi.encodeWithSignature("setX(uint256)", newX);

        uint256 nativeFee = initiator.quoteWithDefaultOptions(address(this), data, gas, value);

        vm.deal(ALICE, 10 ether);

        vm.prank(ALICE);
        initiator.sendWithDefaultOptions{value: nativeFee}(address(this), data, gas, value);

        assertEq(x, newX);
        assertEq(valueDuringSetX, 1 ether);
    }

    function testMothership() public {
        bytes32 originalSender = bytes32(_random());
        while (originalSender == bytes32(0)) originalSender = bytes32(_random());

        uint256 senderType = _random();
        while (senderType == 0) senderType = _random();

        address expected = hub.predictSubAccount(originalSender, senderType);
        assertEq(hub.createSubAccount(originalSender, senderType), expected);

        uint256 newX = _random();

        vm.deal(address(this), 10 ether);

        bytes memory message = abi.encode(
            originalSender,
            senderType,
            expected,
            abi.encodeWithSignature(
                "execute(address,uint256,bytes)", address(this), 1 ether, abi.encodeWithSignature("setX(uint256)", newX)
            )
        );

        hub.forward{value: 1 ether}(message);

        assertEq(x, newX);
        assertEq(valueDuringSetX, 1 ether);
    }

    function setX(uint256 value) public payable {
        valueDuringSetX = msg.value;
        x = value;
    }
}
