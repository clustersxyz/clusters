// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {Pricing} from "../src/Pricing.sol";
import {ClusterData} from "../src/libraries/ClusterData.sol";

contract ClustersTest is Test {
    Pricing public pricing;
    Clusters public clusters;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    address constant PRANKED_ADDRESS = address(13);

    function _toBytes32(string memory smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(smallString);
        require(smallBytes.length <= 32, "name too long");
        return bytes32(smallBytes);
    }

    function setUp() public {
        pricing = new Pricing();
        clusters = new Clusters(address(pricing));
        minPrice = pricing.minAnnualPrice();
        vm.deal(address(this), 1 ether);
    }

    receive() external payable {}

    fallback() external payable {}

    function bytesToAddress(bytes32 _fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_fuzzedBytes)))));
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

    function testCreateCluster() public {
        clusters.create();
        require(clusters.nextClusterId() == 2, "nextClusterId not incremented");
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == address(this), "clusterAddresses error");
        require(clusters.addressLookup(address(this)) == 1, "addressLookup error");
    }

    function testCreateClusterRevertRegistered() public {
        clusters.create();
        vm.expectRevert(NameManager.Registered.selector);
        clusters.create();
    }

    function testAddCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        clusters.create();
        clusters.add(_addr);
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 2, "addresses array length error");
        require(addresses[0] == address(this), "clusterAddresses error");
        require(addresses[1] == _addr, "clusterAddresses error");
        require(clusters.addressLookup(address(this)) == 1, "addressLookup error");
        require(clusters.addressLookup(_addr) == 1, "addressLookup error");
    }

    function testAddClusterRevertNoCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.add(_addr);
    }

    function testAddClusterRevertRegistered(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        clusters.create();
        vm.prank(_addr);
        clusters.create();
        vm.expectRevert(NameManager.Registered.selector);
        clusters.add(_addr);
    }

    function testRemoveCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        clusters.create();
        clusters.add(_addr);
        clusters.remove(_addr);
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == address(this), "clusterAddresses error");
        require(clusters.addressLookup(address(this)) == 1, "addressLookup error");
        require(clusters.addressLookup(_addr) == 0, "addressLookup error");
    }

    function testRemoveClusterRevertUnauthorized(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.assume(_addr != PRANKED_ADDRESS);
        clusters.create();
        clusters.add(_addr);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        vm.expectRevert(NameManager.Unauthorized.selector);
        clusters.remove(_addr);
        vm.stopPrank();
    }

    function testRemoveClusterRevertNoCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.assume(_addr != PRANKED_ADDRESS);
        clusters.create();
        clusters.add(_addr);
        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.remove(_addr);
    }

    function testLeaveCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        clusters.create();
        clusters.add(_addr);
        vm.prank(_addr);
        clusters.leave();
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == address(this), "clusterAddresses error");
        require(clusters.addressLookup(address(this)) == 1, "addressLookup error");
        require(clusters.addressLookup(_addr) == 0, "addressLookup error");
    }

    function testLeaveClusterRevertNoCluster(address _addr) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.assume(_addr != PRANKED_ADDRESS);
        clusters.create();
        clusters.add(_addr);
        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.leave();
    }

    function testLeaveClusterRevertInvalid() public {
        clusters.create();
        clusters.buyName{value: 0.25 ether}("Test Name", 1);
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.leave();
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                NameManager.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function buyName() public {
        clusters.buyName{value: 0.1 ether}("Test Name", 1);
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

    function testBuyName(string memory _name, uint256 _ethAmount) public {
        vm.deal(address(this), 10 ether);
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        clusters.create();
        clusters.buyName{value: _ethAmount}(_name, 1);
        bytes32 name = _toBytes32(_name);
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(clusters.ethBacking(name) == _ethAmount, "ethBacking incorrect");
        require(address(clusters).balance == _ethAmount, "contract balance issue");
    }

    function testBuyNameForAnother(string memory _name, uint256 _ethAmount) public {
        vm.deal(address(this), 10 ether);
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        clusters.create();
        vm.prank(PRANKED_ADDRESS);
        clusters.create();
        clusters.buyName{value: _ethAmount}(_name, 2);
        bytes32 name = _toBytes32(_name);
        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 2, "name not assigned to cluster");
        require(clusters.ethBacking(name) == _ethAmount, "ethBacking incorrect");
        require(address(clusters).balance == _ethAmount, "contract balance issue");
    }

    function testBuyNameRevertNoCluster(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.buyName{value: 0.1 ether}(_name, 1);
    }

    function testBuyNameRevertInvalid() public {
        clusters.create();
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.buyName{value: 0.1 ether}("", 1);
    }

    function testBuyNameRevertInvalidTooLong(string memory _name) public {
        vm.assume(bytes(_name).length > 32);
        clusters.create();
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.buyName{value: 0.1 ether}(_name, 1);
    }

    function testBuyNameRevertInsufficient(string memory _name, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _ethAmount = bound(_ethAmount, 0, 0.01 ether - 1 wei);
        clusters.create();
        vm.expectRevert(NameManager.Insufficient.selector);
        clusters.buyName{value: _ethAmount}(_name, 1);
    }

    function testBuyNameRevertRegistered(string memory _name, uint256 _ethAmount) public {
        vm.deal(address(this), 20 ether);
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        clusters.create();
        clusters.buyName{value: _ethAmount}(_name, 1);
        vm.expectRevert(NameManager.Registered.selector);
        clusters.buyName{value: _ethAmount}(_name, 1);
    }

    function testTransferName() public {
        clusters.create();
        buyName();
        bytes32 name = _toBytes32("Test Name");
        vm.prank(PRANKED_ADDRESS);
        clusters.create();
        clusters.transferName("Test Name", 2);
        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 2, "name not assigned to proper cluster");
        require(clusters.ethBacking(name) == 0.1 ether, "ethBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
    }

    function testTransferName(string memory _name, address _recipient, uint256 _ethAmount) public {
        vm.deal(address(this), 20 ether);
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_recipient != address(this));
        vm.assume(_recipient != address(clusters));
        vm.assume(_recipient != address(0));
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        clusters.create();
        clusters.buyName{value: _ethAmount}(_name, 1);
        vm.prank(_recipient);
        clusters.create();
        clusters.transferName(_name, 2);
        bytes32 name = _toBytes32(_name);
        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameLookup(name) == 2, "name not assigned to proper cluster");
        require(clusters.ethBacking(name) == _ethAmount, "ethBacking incorrect");
        require(address(clusters).balance == _ethAmount, "contract balance issue");
    }

    function testTransferNameRevertNoCluster(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.transferName(_name, 2);
    }

    function testTransferNameRevertUnauthorized(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        vm.expectRevert(NameManager.Unauthorized.selector);
        clusters.transferName(_name, 2);
        vm.stopPrank();
    }

    function testTransferNameRevertInvalid() public {
        clusters.create();
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.buyName{value: 0.1 ether}("", 1);
    }

    function testTransferNameRevertUnregistered(string memory _name, uint256 _toClusterId) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_toClusterId > 1);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.expectRevert(NameManager.Unregistered.selector);
        clusters.transferName(_name, _toClusterId);
    }

    function testTransferNameCanonicalName(string memory _name, address _recipient) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_recipient != address(this));
        vm.assume(_recipient != address(clusters));
        vm.assume(_recipient != address(0));
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        clusters.setCanonicalName(_name);
        bytes32 name = _toBytes32(_name);
        require(clusters.canonicalClusterName(1) == name, "canonicalClusterName error");
        vm.prank(_recipient);
        clusters.create();
        clusters.transferName(_name, 2);
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

    function testPokeName(string memory _name, uint256 _timeSkew) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _timeSkew = bound(_timeSkew, 1, 24 weeks - 1);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        uint256 ethBacking = clusters.ethBacking(name);
        vm.warp(block.timestamp + _timeSkew);
        clusters.pokeName(_name);
        require(clusters.addressLookup(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameLookup(name) == 1, "name not assigned to cluster");
        require(ethBacking > clusters.ethBacking(name), "ethBacking not adjusting");
        require(address(clusters).balance == 0.01 ether, "contract balance issue");
    }

    function testPokeNameRevertInvalid() public {
        clusters.create();
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.pokeName("");
    }

    function testPokeNameRevertUnregistered(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        clusters.create();
        vm.expectRevert(NameManager.Unregistered.selector);
        clusters.pokeName(_name);
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
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.2 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testBidName(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = _bound(_ethAmount, 0.1 ether, 10 ether);
        vm.deal(_bidder, 10 ether);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount}(_name);
        vm.stopPrank();
        bytes32 name = _toBytes32(_name);
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(clusters.nameLookup(name) == 1, "purchaser lost name after bid");
        require(bid.ethAmount == _ethAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == _bidder, "bid bidder incorrect");
        require(address(clusters).balance == 0.1 ether + _ethAmount, "contract balance issue");
    }

    function testBidNameRevertNoCluster(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        vm.deal(_bidder, 10 ether);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.prank(_bidder);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.bidName{value: _ethAmount}(_name);
    }

    function testBidNameRevertInvalid(uint256 _ethAmount) public {
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        vm.deal(address(this), 10 ether);
        clusters.create();
        vm.expectRevert(NameManager.Invalid.selector);
        clusters.bidName{value: _ethAmount}("");
    }

    function testBidNameRevertNoBid(string memory _name, address _bidder) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_bidder != address(this));
        vm.assume(_bidder != address(clusters));
        vm.assume(_bidder != address(0));
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        vm.expectRevert(NameManager.NoBid.selector);
        clusters.bidName{value: 0}(_name);
    }

    function testBidNameRevertUnregistered(string memory _name, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        _ethAmount = bound(_ethAmount, 0.1 ether, 10 ether);
        vm.deal(address(this), 10 ether);
        clusters.create();
        vm.expectRevert(NameManager.Unregistered.selector);
        clusters.bidName{value: _ethAmount}(_name);
    }

    function testBidNameRevertSelfBid(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.expectRevert(NameManager.SelfBid.selector);
        clusters.bidName{value: 0.1 ether}(_name);
    }

    function testBidNameRevertInsufficient(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = bound(_ethAmount, 1 wei, 0.01 ether - 1 wei);
        vm.deal(_bidder, 1 ether);
        vm.deal(PRANKED_ADDRESS, 0.25 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.1 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        vm.expectRevert(NameManager.Insufficient.selector);
        clusters.bidName{value: _ethAmount}(_name);
        vm.stopPrank();
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: 0.25 ether}(_name);
        vm.stopPrank();
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.25 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
        require(address(clusters).balance == 0.35 ether, "contract balance issue");
        vm.prank(_bidder);
        vm.expectRevert(NameManager.Insufficient.selector);
        clusters.bidName{value: 0.25 ether - _ethAmount}(_name);
    }

    function testBidNameIncreaseBid(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount1, uint256 _ethAmount2)
        public
    {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount1 = bound(_ethAmount1, 0.01 ether, 10 ether);
        _ethAmount2 = bound(_ethAmount2, 1 wei, 10 ether);
        vm.deal(_bidder, 20 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount1}(_name);
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _ethAmount1, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == _bidder, "bid bidder incorrect");
        require(address(clusters).balance == 0.01 ether + _ethAmount1, "contract balance issue");
        clusters.bidName{value: _ethAmount2}(_name);
        vm.stopPrank();
        bid = clusters.getBid(name);
        require(bid.ethAmount == _ethAmount1 + _ethAmount2, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == _bidder, "bid bidder incorrect");
        require(address(clusters).balance == 0.01 ether + _ethAmount1 + _ethAmount2, "contract balance issue");
    }

    function testBidNameOutbid(string memory _name, bytes32 _bidder1Salt, bytes32 _bidder2Salt, uint256 _ethAmount)
        public
    {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_bidder1Salt != _bidder2Salt);
        address _bidder1 = bytesToAddress(_bidder1Salt);
        address _bidder2 = bytesToAddress(_bidder2Salt);
        _ethAmount = bound(_ethAmount, 0.01 ether, 10 ether);
        vm.deal(_bidder1, 10 ether);
        vm.deal(_bidder2, 11 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder1);
        clusters.create();
        clusters.bidName{value: _ethAmount}(_name);
        vm.stopPrank();
        uint256 balance = address(_bidder1).balance;
        vm.startPrank(_bidder2);
        clusters.create();
        clusters.bidName{value: _ethAmount + 0.25 ether}(_name);
        vm.stopPrank();
        require(address(_bidder1).balance == balance + _ethAmount, "_bidder1 balance error");
        require(address(clusters).balance == 0.01 ether + _ethAmount + 0.25 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _ethAmount + 0.25 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == _bidder2, "bid bidder incorrect");
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
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0.15 ether, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testReduceBid(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount1, uint256 _ethAmount2) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount1 = bound(_ethAmount1, 0.05 ether, 10 ether);
        _ethAmount2 = bound(_ethAmount2, 1 wei, 0.04 ether - 1 wei);
        vm.deal(_bidder, 10 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount1}(_name);
        uint256 balance = address(_bidder).balance;
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(_name, _ethAmount2);
        vm.stopPrank();
        require(address(_bidder).balance == balance + _ethAmount2, "bidder balance error");
        require(address(clusters).balance == 0.01 ether + _ethAmount1 - _ethAmount2, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == _ethAmount1 - _ethAmount2, "bid ethAmount incorrect");
        // TODO: Update implementation once bid update timestamp handling is added
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == _bidder, "bid bidder incorrect");
    }

    function testReduceBidRevertUnauthorized(
        string memory _name,
        bytes32 _bidderSalt,
        uint256 _ethAmount1,
        uint256 _ethAmount2
    ) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount1 = bound(_ethAmount1, 0.05 ether, 10 ether);
        _ethAmount2 = bound(_ethAmount2, 1 wei, 0.04 ether - 1 wei);
        vm.deal(_bidder, 10 ether);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount1}(_name);
        vm.stopPrank();
        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(NameManager.Unauthorized.selector);
        clusters.reduceBid(_name, _ethAmount2);
    }

    function testReduceBidRevertTimelock(
        string memory _name,
        bytes32 _bidderSalt,
        uint256 _ethAmount,
        uint256 _timeSkew
    ) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = bound(_ethAmount, 0.02 ether, 10 ether);
        _timeSkew = bound(_timeSkew, 1, 30 days - 1);
        vm.deal(_bidder, 10 ether);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount}(_name);
        vm.warp(block.timestamp + _timeSkew);
        vm.expectRevert(NameManager.Timelock.selector);
        clusters.reduceBid(_name, _ethAmount / 2);
        vm.stopPrank();
    }

    // TODO: Test once acceptBid is implemented
    //function testReduceBidRevertNoBid

    function testReduceBidRevertInsufficient(
        string memory _name,
        bytes32 _bidderSalt,
        uint256 _ethAmount1,
        uint256 _ethAmount2
    ) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount1 = bound(_ethAmount1, 0.02 ether, 1 ether);
        _ethAmount2 = bound(_ethAmount2, 1 ether + 1 wei, type(uint256).max - 1 wei);
        vm.deal(_bidder, 10 ether);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount1}(_name);
        vm.warp(block.timestamp + 31 days);
        vm.expectRevert(NameManager.Insufficient.selector);
        clusters.reduceBid(_name, _ethAmount2);
        vm.stopPrank();
    }

    function testReduceBidUint256Max(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = bound(_ethAmount, 0.01 ether, 10 ether);
        vm.deal(_bidder, 10 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount}(_name);
        uint256 balance = address(_bidder).balance;
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(_name, type(uint256).max);
        vm.stopPrank();
        require(address(_bidder).balance == balance + _ethAmount, "bid refund balance error");
        require(address(clusters).balance == 0.01 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testReduceBidTotalBid(string memory _name, bytes32 _bidderSalt, uint256 _ethAmount) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        address _bidder = bytesToAddress(_bidderSalt);
        _ethAmount = bound(_ethAmount, 0.01 ether, 10 ether);
        vm.deal(_bidder, 10 ether);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_bidder);
        clusters.create();
        clusters.bidName{value: _ethAmount}(_name);
        uint256 balance = address(_bidder).balance;
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(_name, _ethAmount);
        vm.stopPrank();
        require(address(_bidder).balance == balance + _ethAmount, "bid refund balance error");
        require(address(clusters).balance == 0.01 ether, "contract balance issue");
        ClusterData.Bid memory bid = clusters.getBid(name);
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
        ClusterData.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testSetCanonicalName(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        clusters.setCanonicalName(_name);
        require(clusters.nameLookup(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameUpdate(string memory _name1, string memory _name2) public {
        vm.assume(bytes(_name1).length > 0);
        vm.assume(bytes(_name1).length <= 32);
        vm.assume(bytes(_name2).length > 0);
        vm.assume(bytes(_name2).length <= 32);
        bytes32 name1 = _toBytes32(_name1);
        bytes32 name2 = _toBytes32(_name2);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name1, 1);
        clusters.buyName{value: 0.01 ether}(_name2, 1);
        clusters.setCanonicalName(_name1);
        clusters.setCanonicalName(_name2);
        require(clusters.nameLookup(name1) == 1, "clusterId error");
        require(clusters.nameLookup(name2) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name2, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 2, "names array length error");
        require(names[0] == name1, "name array error");
        require(names[1] == name2, "name array error");
    }

    function testSetCanonicalNameDelete(string memory _name) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        bytes32 name = _toBytes32(_name);
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        clusters.setCanonicalName(_name);
        clusters.setCanonicalName("");
        require(clusters.nameLookup(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == bytes32(""), "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameRevertUnauthorized(string memory _name, address _notOwner) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_notOwner != address(this));
        vm.assume(_notOwner != address(clusters));
        vm.assume(_notOwner != address(0));
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.startPrank(_notOwner);
        clusters.create();
        vm.expectRevert(NameManager.Unauthorized.selector);
        clusters.setCanonicalName(_name);
        vm.stopPrank();
    }

    function testSetCanonicalNameRevertNoCluster(string memory _name, address _notOwner) public {
        vm.assume(bytes(_name).length > 0);
        vm.assume(bytes(_name).length <= 32);
        vm.assume(_notOwner != address(this));
        vm.assume(_notOwner != address(clusters));
        vm.assume(_notOwner != address(0));
        vm.assume(_notOwner != address(vm));
        clusters.create();
        clusters.buyName{value: 0.01 ether}(_name, 1);
        vm.prank(_notOwner);
        vm.expectRevert(NameManager.NoCluster.selector);
        clusters.setCanonicalName(_name);
    }

    function testSetWalletName(address _addr, string memory _walletName1, string memory _walletName2) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.assume(_addr != address(vm));
        vm.assume(bytes(_walletName1).length > 0);
        vm.assume(bytes(_walletName1).length <= 32);
        vm.assume(bytes(_walletName2).length > 0);
        vm.assume(bytes(_walletName2).length <= 32);
        bytes32 walletName1 = _toBytes32(_walletName1);
        bytes32 walletName2 = _toBytes32(_walletName2);
        clusters.create();
        clusters.setWalletName(_walletName1);
        clusters.add(_addr);
        vm.prank(_addr);
        clusters.setWalletName(_walletName2);
        require(clusters.addressLookup(address(this)) == 1, "clusterId error");
        require(clusters.addressLookup(_addr) == 1, "clusterId error");
        require(clusters.forwardLookup(1, walletName1) == address(this), "forwardLookup error");
        require(clusters.forwardLookup(1, walletName2) == _addr, "forwardLookup error");
        require(clusters.reverseLookup(address(this)) == walletName1, "reverseLookup error");
        require(clusters.reverseLookup(_addr) == walletName2, "reverseLookup error");
    }

    function testSetWalletNameDelete(address _addr, string memory _walletName1, string memory _walletName2) public {
        vm.assume(_addr != address(this));
        vm.assume(_addr != address(clusters));
        vm.assume(_addr != address(0));
        vm.assume(_addr != address(vm));
        vm.assume(bytes(_walletName1).length > 0);
        vm.assume(bytes(_walletName1).length <= 32);
        vm.assume(bytes(_walletName2).length > 0);
        vm.assume(bytes(_walletName2).length <= 32);
        bytes32 walletName1 = _toBytes32(_walletName1);
        bytes32 walletName2 = _toBytes32(_walletName2);
        clusters.create();
        clusters.setWalletName(_walletName1);
        clusters.setWalletName("");
        clusters.add(_addr);
        vm.startPrank(_addr);
        clusters.setWalletName(_walletName2);
        clusters.setWalletName("");
        vm.stopPrank();
        require(clusters.addressLookup(address(this)) == 1, "clusterId error");
        require(clusters.addressLookup(_addr) == 1, "clusterId error");
        require(clusters.forwardLookup(1, walletName1) == address(0), "forwardLookup not purged");
        require(clusters.forwardLookup(1, walletName2) == address(0), "forwardLookup not purged");
        require(clusters.reverseLookup(address(this)) == bytes32(""), "reverseLookup not purged");
        require(clusters.reverseLookup(_addr) == bytes32(""), "reverseLookup not purged");
    }
}
