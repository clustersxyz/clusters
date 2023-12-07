// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

contract EndpointTest is Test {
    PricingHarberger public pricing;
    Endpoint public endpoint;
    Clusters public clusters;
    uint256 public minPrice;
    address public caller;

    uint256 public constant ECDSA_LIMIT = 115792089237316195423570985008687907852837564279074904382605163141518161494337;
    uint256 public immutable SIGNER_KEY = uint256(keccak256(abi.encodePacked("SIGNER")));
    address public immutable SIGNER = vm.addr(SIGNER_KEY);

    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function _prepAddresses(uint256 callerSalt, uint256 ethAmount) internal {
        caller = vm.addr(callerSalt);
        vm.deal(caller, ethAmount);
    }

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint(address(this), SIGNER);
        clusters = new Clusters(address(pricing), address(endpoint), block.timestamp + 7 days);
        endpoint.setClustersAddr(address(clusters));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    function testBuyName(uint256 callerSalt, string memory name) public {
        vm.assume(callerSalt != SIGNER_KEY);
        vm.assume(callerSalt > 0 && callerSalt < ECDSA_LIMIT);
        vm.assume(bytes(name).length > 0 && bytes(name).length <= 32);
        _prepAddresses(callerSalt, minPrice);

        vm.startPrank(SIGNER);
        bytes32 digest = endpoint.getEthSignedMessageHash(caller, name);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        vm.stopPrank();

        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.buyName{value: minPrice}(minPrice, name);

        vm.startPrank(caller);
        clusters.create();
        endpoint.buyName{value: minPrice}(minPrice, name, v, r, s);
        vm.stopPrank();
    }
}
