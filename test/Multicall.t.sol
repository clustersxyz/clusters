// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {IPricing} from "../src/IPricing.sol";
import {PricingFlat} from "../src/PricingFlat.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

contract MulticallTest is Test {
    IPricing public pricing;
    Endpoint public endpoint;
    Clusters public clusters;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    address constant PRANKED_ADDRESS = address(13);
    string constant NAME = "Test Name";

    function setUp() public {
        pricing = new PricingHarberger();
        endpoint = new Endpoint();
        clusters = new Clusters(address(pricing), address(endpoint), address(this));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    receive() external payable {}

    fallback() external payable {}

    function testInternalFunctions() public {
        bytes32 _bytes = _toBytes32("Manual Test");
        string memory name_ = _toString(_removePadding(_bytes));
        assertEq(
            keccak256(abi.encodePacked("Manual Test")), keccak256(abi.encodePacked(name_)), "internal conversion error"
        );
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                MULTICALL TESTS
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testMulticallCreateAdd(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("create()");
        data[1] = abi.encodeWithSignature("add(bytes32)", addrBytes);

        vm.prank(caller);
        clusters.multicall(data);

        bytes32[] memory addresses = clusters.clusterAddresses(1);
        assertEq(clusters.nextClusterId(), 2, "nextClusterId not incremented");
        assertEq(addresses.length, 2, "addresses array length error");
        assertEq(addresses[0], callerBytes, "clusterAddresses error");
        assertEq(addresses[1], addrBytes, "clusterAddresses error");
        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId error");
        assertEq(clusters.addressToClusterId(addrBytes), 1, "addressToClusterId error");
    }

    function testMulticallCreateBuy(bytes32 callerSalt, string memory name, uint256 buyAmount) public {
        vm.assume(bytes(name).length > 0 && bytes(name).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 _name = _toBytes32(name);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("create()");
        data[1] = abi.encodeWithSignature("buyName(uint256,string)", buyAmount, name);

        vm.prank(caller);
        clusters.multicall{value: buyAmount}(data);

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], _name, "name array error");
        assertEq(clusters.nameToClusterId(_name), 1, "name not assigned to cluster");
        assertEq(clusters.nameBacking(_name), buyAmount, "nameBacking incorrect");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                INTERNAL FUNCTIONS
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        return bytes32(smallBytes);
    }

    /// @dev This implementation differs from the onchain implementation as removing both left and right padding is
    /// necessary for fuzz testing.
    function _toString(bytes32 smallBytes) internal pure returns (string memory result) {
        if (smallBytes == bytes32("")) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, smallBytes)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, smallBytes)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }

    /// @dev Used for sanitizing fuzz inputs by removing all left-padding (assume all names are right-padded)
    function _removePadding(bytes32 smallBytes) internal pure returns (bytes32 result) {
        uint256 shift = 0;
        // Determine the amount of left-padding (number of leading zeros)
        while (shift < 32 && smallBytes[shift] == 0) {
            unchecked {
                ++shift;
            }
        }
        if (shift == 0) {
            // No left-padding, return the original data
            return smallBytes;
        }
        if (shift == 32) {
            // All bytes are zeros
            return bytes32(0);
        }
        // Shift bytes to the left
        for (uint256 i = 0; i < 32 - shift; i++) {
            result |= bytes32(uint256(uint8(smallBytes[i + shift])) << (8 * (31 - i)));
        }
        return result;
    }

    function _addressToBytes(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _bytesToAddress(bytes32 fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(fuzzedBytes)))));
    }
}
