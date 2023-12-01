// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";

import {PricingHarbergerHarness} from "./harness/PricingHarbergerHarness.sol";

contract ClustersTest is Test {
    PricingHarbergerHarness public pricing;
    Endpoint public endpoint;
    Clusters public clusters;

    uint256 secondsAfterCreation = 1000 * 365 days;
    uint256 minPrice;

    address constant PRANKED_ADDRESS = address(13);
    string constant NAME = "Test Name";

    function setUp() public {
        pricing = new PricingHarbergerHarness();
        endpoint = new Endpoint();
        clusters = new Clusters(address(pricing), address(clusters));
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
                Clusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testCreateCluster(bytes32 callerSalt) public {
        address caller = _bytesToAddress(callerSalt);

        vm.prank(caller);
        clusters.create();

        require(clusters.nextClusterId() == 2, "nextClusterId not incremented");
        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressToClusterId(caller) == 1, "addressToClusterId error");
    }

    function testCreateClusterRevertRegistered(bytes32 callerSalt) public {
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Registered.selector);
        clusters.create();
        vm.stopPrank();
    }

    function testAddCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 2, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(addresses[1] == addr, "clusterAddresses error");
        require(clusters.addressToClusterId(caller) == 1, "addressToClusterId error");
        require(clusters.addressToClusterId(addr) == 1, "addressToClusterId error");
    }

    function testAddClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.add(addr);
    }

    function testAddClusterRevertRegistered(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.prank(caller);
        clusters.create();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.add(addr);
    }

    function testRemoveCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        clusters.remove(addr);
        vm.stopPrank();

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressToClusterId(caller) == 1, "addressToClusterId error");
        require(clusters.addressToClusterId(addr) == 0, "addressToClusterId error");
    }

    function testRemoveClusterRevertUnauthorized(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

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

    function testRemoveClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.remove(addr);
    }

    function testLeaveCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(addr);
        clusters.remove(addr);

        address[] memory addresses = clusters.clusterAddresses(1);
        require(addresses.length == 1, "addresses array length error");
        require(addresses[0] == caller, "clusterAddresses error");
        require(clusters.addressToClusterId(caller) == 1, "addressToClusterId error");
        require(clusters.addressToClusterId(addr) == 0, "addressToClusterId error");
    }

    function testLeaveClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.remove(PRANKED_ADDRESS);
    }

    function testLeaveClusterRevertInvalid(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}("Test String");
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.remove(caller);
        vm.stopPrank();
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                IClusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testBuyName(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameToClusterId(name) == 1, "name not assigned to cluster");
        require(clusters.nameBacking(name) == buyAmount, "nameBacking incorrect");
        require(address(clusters).balance == buyAmount, "contract balance issue");
    }

    function testBuyNameRevertNoCluster(bytes32 callerSalt, bytes32 name_) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        vm.deal(caller, minPrice);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.buyName{value: minPrice}(_string);
    }

    function testBuyNameRevertInvalid(bytes32 callerSalt) public {
        address caller = _bytesToAddress(callerSalt);
        vm.deal(caller, minPrice);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: minPrice}("");
        vm.stopPrank();
    }

    function testBuyNameRevertInvalidTooLong(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        vm.deal(caller, minPrice);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: minPrice}(name_);
        vm.stopPrank();
    }

    function testBuyNameRevertInsufficient(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, 0, minPrice - 1);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();
    }

    function testBuyNameRevertRegistered(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount * 2);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();
    }

    function testTransferName(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(_string, 2);

        bytes32[] memory names = clusters.getClusterNames(2);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
        require(clusters.nameToClusterId(name) == 2, "name not assigned to proper cluster");
        require(clusters.nameBacking(name) == buyAmount, "nameBacking incorrect");
        require(address(clusters).balance == buyAmount, "contract balance issue");
    }

    function testTransferNameRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.transferName(_string, 2);
    }

    function testTransferNameRevertUnauthorized(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.transferName(_string, 2);
        vm.stopPrank();
    }

    function testTransferNameRevertInvalid(bytes32 callerSalt, uint256 buyAmount) public {
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.buyName{value: buyAmount}("");
        vm.stopPrank();
    }

    function testTransferNameRevertUnregistered(
        bytes32 callerSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 _toClusterId
    ) public {
        vm.assume(name_ != bytes32(""));
        vm.assume(_toClusterId > 1);
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.transferName(_string, _toClusterId);
        vm.stopPrank();
    }

    function testTransferNameCanonicalName(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        clusters.setCanonicalName(_string);
        vm.stopPrank();

        require(
            clusters.canonicalClusterName(1) == _toBytes32(_toString(_removePadding(name_))),
            "canonicalClusterName error"
        );

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(_string, 2);

        require(clusters.canonicalClusterName(1) == bytes32(""), "canonicalClusterName wasn't cleared");
        require(clusters.canonicalClusterName(2) == bytes32(""), "canonicalClusterName possibly transferred");
    }

    function testPokeName(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount, uint256 _timeSkew)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 1, 24 weeks - 1);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.warp(block.timestamp + _timeSkew);
        vm.prank(addr);
        clusters.pokeName(_string);

        require(clusters.addressToClusterId(caller) == 1, "address(this) not assigned to cluster");
        require(clusters.nameToClusterId(name) == 1, "name not assigned to cluster");
        require(buyAmount > clusters.nameBacking(name), "nameBacking not adjusting");
        require(address(clusters).balance == buyAmount, "contract balance issue");
    }

    function testPokeNameRevertInvalid(bytes32 callerSalt) public {
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.pokeName("");
        vm.stopPrank();
    }

    function testPokeNameRevertUnregistered(bytes32 callerSalt, bytes32 name_) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.pokeName(_string);
        vm.stopPrank();
    }

    function testBidName(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount, uint256 bidAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        require(clusters.nameToClusterId(name) == 1, "purchaser lost name after bid");
        require(bid.ethAmount == bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == buyAmount + bidAmount, "contract balance issue");
    }

    function testBidNameRevertNoCluster(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.bidName{value: bidAmount}(_string);
    }

    function testBidNameRevertInvalid(bytes32 callerSalt, uint256 buyAmount) public {
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.bidName{value: buyAmount}("");
        vm.stopPrank();
    }

    function testBidNameRevertNoBid(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.bidName{value: 0}(_string);
    }

    function testBidNameRevertUnregistered(bytes32 callerSalt, bytes32 name_, uint256 bidAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();
    }

    function testBidNameRevertSelfBid(bytes32 callerSalt, bytes32 name_, uint256 buyAmount, uint256 bidAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount + bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.expectRevert(IClusters.SelfBid.selector);
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();
    }

    function testBidNameRevertInsufficient(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 2, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, minPrice + 1);
        vm.deal(PRANKED_ADDRESS, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice - 1}(_string);
        vm.stopPrank();

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
        require(address(clusters).balance == buyAmount + bidAmount, "contract balance issue");

        vm.prank(addr);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice + 1}(_string);
    }

    function testBidNameIncreaseBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 _bidIncrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        _bidIncrease = bound(_bidIncrease, 1, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount + _bidIncrease);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);

        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == bidAmount, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == buyAmount + bidAmount, "contract balance issue");

        clusters.bidName{value: _bidIncrease}(_string);
        vm.stopPrank();

        bid = clusters.getBid(name);
        require(bid.ethAmount == bidAmount + _bidIncrease, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
        require(address(clusters).balance == buyAmount + bidAmount + _bidIncrease, "contract balance issue");
    }

    function testBidNameOutbid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);
        vm.deal(PRANKED_ADDRESS, bidAmount + 1);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();
        uint256 balance = address(addr).balance;

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: bidAmount + 1}(_string);
        vm.stopPrank();

        require(address(addr).balance == balance + bidAmount, "_bidder1 balance error");
        require(address(clusters).balance == buyAmount + bidAmount + 1, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == bidAmount + 1, "bid ethAmount incorrect");
        require(bid.createdTimestamp == block.timestamp, "bid createdTimestamp incorrect");
        require(bid.bidder == PRANKED_ADDRESS, "bid bidder incorrect");
    }

    function testReduceBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 1, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(_string, bidDecrease);
        vm.stopPrank();

        require(address(addr).balance == balance + bidDecrease, "bidder balance error");
        require(address(clusters).balance == buyAmount + bidAmount - bidDecrease, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        // TODO: Update implementation once bid update timestamp handling is added
        require(bid.createdTimestamp == block.timestamp - 31 days, "bid createdTimestamp incorrect");
        require(bid.bidder == addr, "bid bidder incorrect");
    }

    function testReduceBidRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 1, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.reduceBid(_string, bidDecrease);
    }

    function testReduceBidRevertTimelock(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease,
        uint256 _timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice * 2, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        _timeSkew = bound(_timeSkew, 1, 30 days - 1);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);

        vm.warp(block.timestamp + _timeSkew);
        vm.expectRevert(IClusters.Timelock.selector);
        clusters.reduceBid(_string, bidDecrease);
        vm.stopPrank();
    }

    // TODO: Test once acceptBid is implemented
    //function testReduceBidRevertNoBid

    function testReduceBidRevertInsufficient(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease,
        uint256 _timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice * 2, 10 ether);
        bidDecrease = bound(bidDecrease, bidAmount + 1, 20 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);

        vm.warp(block.timestamp + _timeSkew);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.reduceBid(_string, bidDecrease);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.reduceBid(_string, bidAmount - 1);
        vm.stopPrank();
    }

    function testReduceBidUint256Max(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 _timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + _timeSkew);
        clusters.reduceBid(_string, type(uint256).max);
        vm.stopPrank();

        require(address(addr).balance == balance + bidAmount, "bid refund balance error");
        require(address(clusters).balance == buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testReduceBidTotalBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 _timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        _timeSkew = bound(_timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(_string);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + _timeSkew);
        clusters.reduceBid(_string, bidAmount);
        vm.stopPrank();

        require(address(addr).balance == balance + bidAmount, "bid refund balance error");
        require(address(clusters).balance == buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testRevokeBid() public {
        clusters.create();
        clusters.buyName{value: 0.1 ether}(NAME);
        bytes32 name = _toBytes32(NAME);
        vm.deal(PRANKED_ADDRESS, 1 ether);
        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: 0.2 ether}(NAME);
        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(NAME, 0.2 ether);
        vm.stopPrank();
        require(clusters.addressToClusterId(address(this)) == 1, "address(this) not assigned to cluster");
        require(clusters.nameToClusterId(name) == 1, "name not assigned to cluster");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(name == names[0], "cluster name array incorrect");
        require(clusters.nameBacking(name) < 0.1 ether, "nameBacking incorrect");
        require(address(clusters).balance == 0.1 ether, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        require(bid.ethAmount == 0, "bid ethAmount not purged");
        require(bid.createdTimestamp == 0, "bid createdTimestamp not purged");
        require(bid.bidder == address(0), "bid bidder not purged");
    }

    function testSetCanonicalName(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        clusters.setCanonicalName(_string);
        vm.stopPrank();

        require(clusters.nameToClusterId(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameUpdate(bytes32 callerSalt, bytes32 name_1, bytes32 name_2, uint256 buyAmount) public {
        vm.assume(name_1 != bytes32(""));
        vm.assume(name_2 != bytes32(""));
        vm.assume(name_1 != name_2);
        address caller = _bytesToAddress(callerSalt);
        string memory _string1 = _toString(_removePadding(name_1));
        bytes32 name1 = _toBytes32(_string1);
        string memory _string2 = _toString(_removePadding(name_2));
        bytes32 name2 = _toBytes32(_string2);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount * 2);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string1);
        clusters.buyName{value: buyAmount}(_string2);
        clusters.setCanonicalName(_string1);
        clusters.setCanonicalName(_string2);
        vm.stopPrank();

        require(clusters.nameToClusterId(name1) == 1, "clusterId error");
        require(clusters.nameToClusterId(name2) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == name2, "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 2, "names array length error");
        require(names[0] == name1, "name array error");
        require(names[1] == name2, "name array error");
    }

    function testSetCanonicalNameDelete(bytes32 callerSalt, bytes32 name_, uint256 buyAmount) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        clusters.setCanonicalName(_string);
        clusters.setCanonicalName("");
        vm.stopPrank();

        require(clusters.nameToClusterId(name) == 1, "clusterId error");
        require(clusters.canonicalClusterName(1) == bytes32(""), "canonicalClusterName error");
        bytes32[] memory names = clusters.getClusterNames(1);
        require(names.length == 1, "names array length error");
        require(names[0] == name, "name array error");
    }

    function testSetCanonicalNameRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        bytes32 name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Unauthorized.selector);
        clusters.setCanonicalName(_string);
        vm.stopPrank();
    }

    function testSetCanonicalNameRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_, uint256 buyAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(_string);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.setCanonicalName(_string);
    }

    function testSetWalletName(bytes32 callerSalt, bytes32 name_) public {
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);
        vm.assume(name != bytes32(""));

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(caller, _string);
        vm.stopPrank();

        assertEq(clusters.addressToClusterId(caller), 1, "addressToClusterId failed");
        assertEq(clusters.forwardLookup(1, name), caller, "forwardLookup failed");
        assertEq(clusters.reverseLookup(caller), name, "reverseLookup failed");
    }

    function testSetWalletNameOther(bytes32 callerSalt, bytes32 addrSalt, bytes32 name_) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addr);
        vm.stopPrank();

        vm.prank(addr);
        clusters.setWalletName(addr, _string);

        assertEq(clusters.addressToClusterId(addr), 1, "addressToClusterId failed");
        assertEq(clusters.forwardLookup(1, name), addr, "forwardLookup failed");
        assertEq(clusters.reverseLookup(addr), name, "reverseLookup failed");
    }

    function testSetWalletNameDelete(bytes32 callerSalt, bytes32 name_) public {
        vm.assume(name_ != bytes32(""));
        address caller = _bytesToAddress(callerSalt);
        string memory _string = _toString(_removePadding(name_));
        bytes32 name = _toBytes32(_string);

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(caller, _string);
        clusters.setWalletName(caller, "");
        vm.stopPrank();

        require(clusters.addressToClusterId(caller) == 1, "clusterId error");
        require(clusters.forwardLookup(1, name) == address(0), "forwardLookup not purged");
        require(clusters.reverseLookup(caller) == bytes32(""), "reverseLookup not purged");
    }

    function _toBytes32(string memory _smallString) internal pure returns (bytes32 result) {
        bytes memory smallBytes = bytes(_smallString);
        require(smallBytes.length <= 32, "name too long");
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

    function _bytesToAddress(bytes32 fuzzedBytes) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(fuzzedBytes)))));
    }
}
