// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {IClusters} from "../src/IClusters.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    address constant PRANKED_ADDRESS = address(13);

    function _toBytes32(string memory _smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(_smallString);
        require(smallBytes.length <= 32, "name too long");
        return bytes32(smallBytes);
    }

    /// @dev This implementation differs from the onchain implementation as removing both left and right padding is
    /// necessary for fuzz testing.
    function _toString(bytes32 _smallBytes) internal pure returns (string memory result) {
        if (_smallBytes == bytes32("")) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, _smallBytes)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, _smallBytes)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }

    /// @dev Used for sanitizing fuzz inputs by removing all left-padding (assume all names are right-padded)
    function _removePadding(bytes32 _smallBytes) internal pure returns (bytes32 result) {
        uint256 shift = 0;
        // Determine the amount of left-padding (number of leading zeros)
        while (shift < 32 && _smallBytes[shift] == 0) {
            unchecked {
                ++shift;
            }
        }
        if (shift == 0) {
            // No left-padding, return the original data
            return _smallBytes;
        }
        if (shift == 32) {
            // All bytes are zeros
            return bytes32(0);
        }
        // Shift bytes to the left
        for (uint256 i = 0; i < 32 - shift; i++) {
            result |= bytes32(uint256(uint8(_smallBytes[i + shift])) << (8 * (31 - i)));
        }
        return result;
    }

    function _bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
    }

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    receive() external payable {}

    fallback() external payable {}

    function testInternalFunctions() public pure {
        bytes32 _bytes = _toBytes32("Manual Test");
        string memory _string = _toString(_removePadding(_bytes));
        require(
            keccak256(abi.encodePacked("Manual Test")) == keccak256(abi.encodePacked(_string)),
            "internal conversion error"
        );
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                Pricing.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testDecayMultiplier() public {
        int256 decay = pricing.getDecayMultiplier(730 days);
        assertEq(decay, int256(0.25e18 - 1)); // Tiny error tolerance is okay
    }

    function testIntegratedDecayPrice() public {
        uint256 spent = pricing.getIntegratedDecayPrice(1 ether, 730 days);
        assertEq(spent, 1082021280666722556); // 1.08 ether over 2 years
    }

    function testIntegratedPriceSimpleMin() public {
        (uint256 simpleMinSpent, uint256 simpleMinPrice) =
            pricing.getIntegratedPrice(minPrice, 730 days, secondsAfterCreation);
        assertEq(simpleMinSpent, 2 * minPrice);
        assertEq(simpleMinPrice, minPrice);
    }

    function testIntegratedPriceSimpleDecay() public {
        (uint256 simpleDecaySpent, uint256 simpleDecayPrice) =
            pricing.getIntegratedPrice(1 ether, 730 days, secondsAfterCreation);
        assertEq(simpleDecaySpent, 1082021280666722556); // 1.08 ether over 2 years
        assertEq(simpleDecayPrice, 0.25e18 - 1); // Cut in half every year, now a quarter of start price
    }

    function testIntegratedPriceSimpleDecay2() public {
        (uint256 simpleDecaySpent2, uint256 simpleDecayPrice2) =
            pricing.getIntegratedPrice(1 ether, 209520648, secondsAfterCreation);
        assertEq(simpleDecaySpent2, 1428268090226162139); // 1.42 ether over 6.64 years
        assertEq(simpleDecayPrice2, 10000000175998132); // ~0.01 price after 6.64 years
    }

    function testIntegratedPriceComplexDecay() public {
        (uint256 complexDecaySpent, uint256 complexDecayPrice) =
            pricing.getIntegratedPrice(1 ether, 10 * 365 days, secondsAfterCreation);
        assertEq(complexDecaySpent, 1461829528582326522); // 1.42 ether over 6.6 years then 0.03 ether over 3 years
        assertEq(complexDecayPrice, minPrice);
    }

    function testIntegratedPriceSimpleMax() public {
        (uint256 simpleMaxSpent, uint256 simpleMaxPrice) = pricing.getIntegratedPrice(1 ether, 365 days, 365 days);
        assertEq(simpleMaxSpent, 0.025 ether);
        assertEq(simpleMaxPrice, 0.5 ether - 1); // Actual price has decayed by half before being truncated by max
    }

    function testIntegratedPriceMaxToMiddleRange() public {
        (uint256 maxToMiddleSpent, uint256 maxToMiddlePrice) =
            pricing.getIntegratedPrice(0.025 ether, 365 days, 365 days);
        assertEq(maxToMiddleSpent, 18033688011112042); // 0.018 ether for 1 year that dips from max into middle
        assertEq(maxToMiddlePrice, 0.0125 ether - 1);
    }

    function testIntegratedPriceMaxToMinRange() public {
        (uint256 maxToMinSpent, uint256 maxToMinPrice) = pricing.getIntegratedPrice(0.025 ether, 730 days, 730 days);
        assertEq(maxToMinSpent, 28421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);

        (maxToMinSpent, maxToMinPrice) = pricing.getIntegratedPrice(0.025 ether, 3 * 365 days, 3 * 365 days);
        assertEq(maxToMinSpent, 38421144664460826); // 0.028 ether for 2 year that dips from max into middle to min
        assertEq(maxToMinPrice, 0.01 ether);
    }

    function testPriceAfterBid() public {
        uint256 newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 0);
        assertEq(newPrice, 1 ether);

        newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 15 days);
        assertEq(newPrice, 1.25 ether);

        newPrice = pricing.getPriceAfterBid(1 ether, 2 ether, 30 days);
        assertEq(newPrice, 2 ether);
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                Clusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testCreateCluster(bytes32 _callerSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);

        vm.prank(caller);
        clusters.create();

        require(clusters.nextClusterId() == 2, "nextClusterId not incremented");
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressLookup(caller) == 1, "addressLookup error");
    }

    function testCreateClusterRevertRegistered(bytes32 _callerSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Registered.selector);
        clusters.create();
        vm.stopPrank();
    }

    function testAddCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 2, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(addresses[1] == addr, "clusterAddresses error");
        require(clusters.addressLookup(caller) == 1, "addressLookup error");
        require(clusters.addressLookup(addr) == 1, "addressLookup error");
    }

    function testAddClusterRevertNoCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.add(addr);
    }

    function testAddClusterRevertRegistered(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.prank(caller);
        clusters.create();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.add(addr);
    }

    function testRemoveCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        clusters.remove(addr);
        vm.stopPrank();

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressLookup(caller) == 1, "addressLookup error");
        require(clusters.addressLookup(addr) == 0, "addressLookup error");
    }

    function testRemoveClusterRevertUnauthorized(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.remove(addr);
        vm.stopPrank();
    }

    function testRemoveClusterRevertNoCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.remove(addr);
    }

    function testLeaveCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(addr);
        clusters.leave();

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressLookup(caller) == 1, "addressLookup error");
        require(clusters.addressLookup(addr) == 0, "addressLookup error");
    }

    function testLeaveClusterRevertNoCluster(bytes32 _callerSalt, bytes32 _addrSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.leave();
    }

    function testLeaveClusterRevertInvalid(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}("Test String");
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.leave();
        vm.stopPrank();
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                IClusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function buyName() public {
        clusters.buyName{value: 0.1 ether}("Test Name");
    }

    function testBuyName() public {
        clusters.create();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testBuyName(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == _buyAmount, "ethBacking incorrect");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
    }

    function testBuyNameForAnother(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.prank(caller);
        clusters.create();

        vm.prank(PRANKED_ADDRESS);
        clusters.create();

        vm.prank(caller);
        clusters.buyName{value: _buyAmount}(_string);

        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 2, "name not assigned to cluster");
        require(clusters.ethBacking(name) == _buyAmount, "ethBacking incorrect");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
    }

    function testBuyNameRevertNoCluster(bytes32 _callerSalt, bytes32 _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        vm.deal(caller, minPrice);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.buyName{value: minPrice}(_string);
    }

    function testBuyNameRevertInvalid(bytes32 _callerSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        vm.deal(caller, minPrice);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: minPrice}("");
        vm.stopPrank();
    }

    function testBuyNameRevertInvalidTooLong(bytes32 _callerSalt, string memory _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(bytes(_name).length > 32);
        address caller = _bytesToAddress(_callerSalt);
        vm.deal(caller, minPrice);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: minPrice}(_name);
        vm.stopPrank();
    }

    function testBuyNameRevertInsufficient(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, 0, minPrice - 1);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();
    }

    function testBuyNameRevertRegistered(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount * 2);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();
    }

    function testTransferName(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(_string, 2);

        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 2, "name not assigned to proper cluster");
        require(clusters.ethBacking(name) == _buyAmount, "ethBacking incorrect");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
    }

    function testTransferNameRevertNoCluster(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.transferName(_string, 2);
    }

    function testTransferNameRevertUnauthorized(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.transferName(_string, 2);
        vm.stopPrank();
    }

    function testTransferNameRevertInvalid(bytes32 _callerSalt, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: _buyAmount}("");
        vm.stopPrank();
    }

    function testTransferNameRevertUnregistered(
        bytes32 _callerSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _toClusterId
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        vm.assume(_toClusterId > 1);
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.transferName(_string, _toClusterId);
        vm.stopPrank();
    }

    function testTransferNameCanonicalName(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        clusters.setCanonicalName(_string);
        vm.stopPrank();

        require(
            clusters.canonicalClusterName(1) == _toBytes32(_toString(_removePadding(_name))),
            "canonicalClusterName error"
        );

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(_string, 2);

        require(clusters.canonicalClusterName(1) == bytes32(""), "canonicalClusterName wasn't cleared");
        require(clusters.canonicalClusterName(2) == bytes32(""), "canonicalClusterName possibly transferred");
    }

    function testPokeName() public {
        clusters.create();
        buyName();
        vm.prank(PRANKED_ADDRESS);
        clusters.pokeName("Test Name");
        bytes32 name = _toBytes32("Test Name");
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testPokeName(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount, uint256 _timeSkew)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 1, 24 weeks - 1);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.warp(block.timestamp + _timeSkew);
        vm.prank(addr);
        clusters.pokeName(_string);

        require(clusters.addressLookup(caller) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(_buyAmount > clusters.ethBacking(name), "ethBacking not adjusting");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
    }

    function testPokeNameRevertInvalid(bytes32 _callerSalt) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.pokeName("");
        vm.stopPrank();
    }

    function testPokeNameRevertUnregistered(bytes32 _callerSalt, bytes32 _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.pokeName(_string);
        vm.stopPrank();
    }

    function testBidName() public {
        clusters.create();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(PRANKED_ADDRESS, 1 ether);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: 0.2 ether}("Test Name");
        vm.stopPrank();
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.3 ether, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.2 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testBidName(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount, uint256 _bidAmount)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        require(clusters.nameLookup(name) == 1, "purchaser lost name after bid");
        require(bid.ethAmount == _bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == _buyAmount + _bidAmount, "contract balance issue");
    }

    function testBidNameRevertNoCluster(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.bidName{value: _bidAmount}(_string);
    }

    function testBidNameRevertInvalid(bytes32 _callerSalt, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.bidName{value: _buyAmount}("");
        vm.stopPrank();
    }

    function testBidNameRevertNoBid(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.bidName{value: 0}(_string);
    }

    function testBidNameRevertUnregistered(bytes32 _callerSalt, bytes32 _name, uint256 _bidAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        vm.deal(caller, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();
    }

    function testBidNameRevertSelfBid(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount, uint256 _bidAmount)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount + _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.expectRevert(IClusters.SelfBid.selector);
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();
    }

    function testBidNameRevertInsufficient(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice + 2, 10 ether);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, minPrice + 1);
        vm.deal(PRANKED_ADDRESS, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice - 1}(_string);
        vm.stopPrank();

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
        require(address(clusters).balance == _buyAmount + _bidAmount, "contract balance issue");

        vm.prank(addr);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice + 1}(_string);
    }

    function testBidNameIncreaseBid(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _bidIncrease
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        _bidIncrease = bound(_bidIncrease, 1, 10 ether);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount + _bidIncrease);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);

        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == _buyAmount + _bidAmount, "contract balance issue");

        clusters.bidName{value: _bidIncrease}(_string);
        vm.stopPrank();

        bid = clusters.getBid(name);
        require(bid.ethAmount == _bidAmount + _bidIncrease, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == _buyAmount + _bidAmount + _bidIncrease, "contract balance issue");
    }

    function testBidNameOutbid(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);
        vm.deal(PRANKED_ADDRESS, _bidAmount + 1);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();
        uint256 balance = address(addr).balance;

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: _bidAmount + 1}(_string);
        vm.stopPrank();

        require(address(addr).balance == balance + _bidAmount, "_bidder1 balance error");
        require(address(clusters).balance == _buyAmount + _bidAmount + 1, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _bidAmount + 1, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testReduceBid() public {
        clusters.create();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(PRANKED_ADDRESS, 1 ether);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: 0.2 ether}("Test Name");
        uint256 balance = PRANKED_ADDRESS.balance;
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid("Test Name", 0.05 ether);
        vm.stopPrank();
        require(PRANKED_ADDRESS.balance == balance + 0.05 ether, "refund error");
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) < 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.25 ether, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.15 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testReduceBid(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _bidDecrease
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice + 1, 10 ether);
        _bidDecrease = bound(_bidDecrease, 1, _bidAmount - minPrice);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(_string, _bidDecrease);
        vm.stopPrank();

        require(address(addr).balance == balance + _bidDecrease, "bidder balance error");
        require(address(clusters).balance == _buyAmount + _bidAmount - _bidDecrease, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        // TODO: Update implementation once bid update timestamp handling is added
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
    }

    function testReduceBidRevertUnauthorized(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _bidDecrease
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice + 1, 10 ether);
        _bidDecrease = bound(_bidDecrease, 1, _bidAmount - minPrice);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.reduceBid(_string, _bidDecrease);
    }

    function testReduceBidRevertTimelock(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _bidDecrease,
        uint256 _timeSkew
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice * 2, 10 ether);
        _bidDecrease = bound(_bidDecrease, 1, _bidAmount - minPrice);
        _timeSkew = bound(_timeSkew, 1, 30 days - 1);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);

        vm.warp(block.timestamp + _timeSkew);
        vm.expectRevert(IClusters.Timelock.selector);
        clusters.reduceBid(_string, _bidDecrease);
        vm.stopPrank();
    }

    // TODO: Test once acceptBid is implemented
    //function testReduceBidRevertNoBid

    function testReduceBidRevertInsufficient(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _bidDecrease,
        uint256 _timeSkew
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice * 2, 10 ether);
        _bidDecrease = bound(_bidDecrease, _bidAmount + 1, 20 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);

        vm.warp(block.timestamp + _timeSkew);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.reduceBid(_string, _bidDecrease);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.reduceBid(_string, _bidAmount - 1);
        vm.stopPrank();
    }

    function testReduceBidUint256Max(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _timeSkew
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + _timeSkew);
        clusters.reduceBid(_string, type(uint256).max);
        vm.stopPrank();

        require(address(addr).balance == balance + _bidAmount, "bid refund balance error");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testReduceBidTotalBid(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount,
        uint256 _bidAmount,
        uint256 _timeSkew
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        _bidAmount = bound(_bidAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, _buyAmount);
        vm.deal(addr, _bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: _bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + _timeSkew);
        clusters.reduceBid(_string, _bidAmount);
        vm.stopPrank();

        require(address(addr).balance == balance + _bidAmount, "bid refund balance error");
        require(address(clusters).balance == _buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testRevokeBid() public {
        clusters.create();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.deal(PRANKED_ADDRESS, 1 ether);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: 0.2 ether}("Test Name");
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid("Test Name", 0.2 ether);
        vm.stopPrank();
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.ethBacking(name) < 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testSetCanonicalName(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        clusters.setCanonicalName(_string);
        vm.stopPrank();

        require(clusters.nameLookup(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameUpdate(bytes32 _callerSalt, bytes32 _name1, bytes32 _name2, uint256 _buyAmount)
        public
    {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name1 != bytes32(""));
        vm.assume(_name2 != bytes32(""));
        vm.assume(_name1 != _name2);
        address caller = _bytesToAddress(_callerSalt);
        string memory _string1 = _toString(_removePadding(_name1));
        bytes32 name1 = _toBytes32(_string1);
        string memory _string2 = _toString(_removePadding(_name2));
        bytes32 name2 = _toBytes32(_string2);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount * 2);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string1);
        clusters.buyName{value: _buyAmount}(_string2);
        clusters.setCanonicalName(_string1);
        clusters.setCanonicalName(_string2);
        vm.stopPrank();

        require(clusters.nameLookup(name1) == 1, "clusterId error");
        require(clusters.nameLookup(name2) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name2, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 2, "names array length error");
        require(names[0] == name1, "name array error");
        require(names[1] == name2, "name array error");
    }

    function testSetCanonicalNameDelete(bytes32 _callerSalt, bytes32 _name, uint256 _buyAmount) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        clusters.setCanonicalName(_string);
        clusters.setCanonicalName("");
        vm.stopPrank();

        require(clusters.nameLookup(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == bytes32(""), "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameRevertUnauthorized(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.setCanonicalName(_string);
        vm.stopPrank();
    }

    function testSetCanonicalNameRevertNoCluster(
        bytes32 _callerSalt,
        bytes32 _addrSalt,
        bytes32 _name,
        uint256 _buyAmount
    ) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        _buyAmount = bound(_buyAmount, minPrice, 10 ether);
        vm.deal(caller, _buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: _buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.setCanonicalName(_string);
    }

    function testSetWalletName(bytes32 _callerSalt, bytes32 _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(caller, _string);
        vm.stopPrank();

        require(clusters.addressLookup(caller) == 1, "clusterId error");
        require(clusters.forwardLookup(1, name) == caller, "forwardLookup error");
        require(clusters.reverseLookup(caller) == _name, "reverseLookup error");
    }

    function testSetWalletNameOther(bytes32 _callerSalt, bytes32 _addrSalt, bytes32 _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_addrSalt != bytes32(""));
        vm.assume(_callerSalt != _addrSalt);
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        address addr = _bytesToAddress(_addrSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(addr);
        clusters.setWalletName(addr, _string);

        require(clusters.addressLookup(addr) == 1, "clusterId error");
        require(clusters.forwardLookup(1, name) == addr, "forwardLookup error");
        require(clusters.reverseLookup(addr) == _name, "reverseLookup error");
    }

    function testSetWalletNameDelete(bytes32 _callerSalt, bytes32 _name) public {
        vm.assume(_callerSalt != bytes32(""));
        vm.assume(_name != bytes32(""));
        address caller = _bytesToAddress(_callerSalt);
        string memory _string = _toString(_removePadding(_name));
        bytes32 name = _toBytes32(_string);

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(caller, _string);
        clusters.setWalletName(caller, "");
        vm.stopPrank();

        require(clusters.addressLookup(caller) == 1, "clusterId error");
        require(clusters.forwardLookup(1, name) == address(0), "forwardLookup not purged");
        require(clusters.reverseLookup(caller) == bytes32(""), "reverseLookup not purged");
    }
}
