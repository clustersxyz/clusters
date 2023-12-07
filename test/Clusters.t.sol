// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../lib/forge-std/src/Test.sol";
import {Clusters, NameManager} from "../src/Clusters.sol";
import {IPricing} from "../src/IPricing.sol";
import {PricingFlat} from "../src/PricingFlat.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IClusters} from "../src/IClusters.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";

contract ClustersTest is Test {
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
                Clusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    function testMulticall() public {
        bytes32 callerSalt = "caller";
        bytes32 addrSalt = "addr";
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        clusters.openMarket();

        vm.startPrank(caller);
        vm.deal(caller, minPrice);
        clusters.create();
        clusters.buyName{value: minPrice}(minPrice, "foobar");
        bytes[] memory batchData = new bytes[](2);
        batchData[0] = abi.encodeWithSignature("add(bytes32)", addrBytes);
        batchData[1] = abi.encodeWithSignature("setWalletName(bytes32,string)", addrBytes, "hot");
        clusters.multicall(batchData);
        vm.stopPrank();
    }

    function testCreateCluster(bytes32 callerSalt) public {
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);

        vm.prank(caller);
        clusters.create();

        assertEq(clusters.nextClusterId(), 2, "nextClusterId not incremented");
        bytes32[] memory addresses = clusters.clusterAddresses(1);
        assertEq(addresses.length, 1, "addresses array length error");
        assertEq(addresses[0], callerBytes, "clusterAddresses error");
        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId error");
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
        bytes32 callerBytes = _addressToBytes(caller);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        bytes32[] memory addresses = clusters.clusterAddresses(1);
        assertEq(addresses.length, 2, "addresses array length error");
        assertEq(addresses[0], callerBytes, "clusterAddresses error");
        assertEq(addresses[1], addrBytes, "clusterAddresses error");
        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId error");
        assertEq(clusters.addressToClusterId(addrBytes), 1, "addressToClusterId error");
    }

    function testAddClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.add(addrBytes);
    }

    function testAddClusterRevertRegistered(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.prank(caller);
        clusters.create();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.add(addrBytes);
    }

    function testRemoveCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        clusters.remove(addrBytes);
        vm.stopPrank();

        bytes32[] memory addresses = clusters.clusterAddresses(1);
        assertEq(addresses.length, 1, "addresses array length error");
        assertEq(addresses[0], callerBytes, "clusterAddresses error");
        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId error");
        assertEq(clusters.addressToClusterId(addrBytes), 0, "addressToClusterId error");
    }

    function testRemoveClusterRevertUnauthorized(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        vm.expectRevert(Ownable.Unauthorized.selector);
        clusters.remove(addrBytes);
        vm.stopPrank();
    }

    function testRemoveClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.remove(addrBytes);
    }

    function testLeaveCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        vm.prank(addr);
        clusters.remove(addrBytes);

        bytes32[] memory addresses = clusters.clusterAddresses(1);
        assertEq(addresses.length, 1, "addresses array length error");
        assertEq(addresses[0], callerBytes, "clusterAddresses error");
        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId error");
        assertEq(clusters.addressToClusterId(addrBytes), 0, "addressToClusterId error");
    }

    function testLeaveClusterRevertNoCluster(bytes32 callerSalt, bytes32 addrSalt) public {
        vm.assume(callerSalt != addrSalt);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.remove(_addressToBytes(PRANKED_ADDRESS));
    }

    function testLeaveClusterRevertInvalid(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.expectRevert(IClusters.Invalid.selector);
        clusters.remove(callerBytes);
        vm.stopPrank();
    }

    /*\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\
                IClusters.sol
    \\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\//\\*/

    /// buyName() TESTS ///

    function testBuyName(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(clusters.nameToClusterId(name), 1, "name not assigned to cluster");
        assertEq(clusters.nameBacking(name), buyAmount, "nameBacking incorrect");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testBuyNameRevertInvalidName(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();
    }

    function testBuyNameRevertNoCluster(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.buyName{value: buyAmount}(buyAmount, name_);
    }

    function testBuyNameRevertRegistered(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount * 2);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.expectRevert(IClusters.Registered.selector);
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();
    }

    function testBuyNameRevertInsufficient(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, 0, minPrice - 1);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();
    }

    /// fundName() TESTS ///

    function testFundName(bytes32 callerSalt, string memory name_, uint256 buyAmount, uint256 fundAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        fundAmount = bound(fundAmount, 0, 10 ether);
        vm.deal(caller, buyAmount + fundAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        clusters.fundName{value: fundAmount}(fundAmount, name_);
        vm.stopPrank();

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(clusters.nameToClusterId(name), 1, "name not assigned to cluster");
        assertEq(clusters.nameBacking(name), buyAmount + fundAmount, "nameBacking incorrect");
        assertEq(address(clusters).balance, buyAmount + fundAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testFundNameNotOwner(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 fundAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        fundAmount = bound(fundAmount, 0, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, fundAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.prank(addr);
        clusters.fundName{value: fundAmount}(fundAmount, name_);

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(clusters.nameToClusterId(name), 1, "name not assigned to cluster");
        assertEq(clusters.nameBacking(name), buyAmount + fundAmount, "nameBacking incorrect");
        assertEq(address(clusters).balance, buyAmount + fundAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testFundNameRevertInvalidName(bytes32 callerSalt, string memory name_, uint256 fundAmount) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        fundAmount = bound(fundAmount, minPrice, 10 ether);
        vm.deal(caller, fundAmount);

        vm.prank(caller);
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.fundName{value: fundAmount}(fundAmount, name_);
    }

    function testFundNameRevertUnregistered(bytes32 callerSalt, string memory name_, uint256 fundAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        fundAmount = bound(fundAmount, minPrice, 10 ether);
        vm.deal(caller, fundAmount);

        vm.prank(caller);
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.fundName{value: fundAmount}(fundAmount, name_);
    }

    /// transferName() TESTS ///

    function testTransferName(bytes32 callerSalt, bytes32 addrSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(name_, 2);

        bytes32[] memory names = clusters.getClusterNamesBytes32(2);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(clusters.nameToClusterId(name), 2, "name not assigned to proper cluster");
        assertEq(clusters.nameBacking(name), buyAmount, "nameBacking incorrect");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testTransferNamePurgesDefaultClusterName(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        clusters.setDefaultClusterName(name_);
        vm.stopPrank();

        assertEq(clusters.defaultClusterName(1), _toBytes32(name_), "defaultClusterName error");

        vm.prank(addr);
        clusters.create();

        vm.prank(caller);
        clusters.transferName(name_, 2);

        assertEq(clusters.defaultClusterName(1), bytes32(""), "defaultClusterName wasn't cleared");
        assertEq(clusters.defaultClusterName(2), bytes32(""), "defaultClusterName possibly transferred");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testTransferNameRevertInvalidName(bytes32 callerSalt, string memory name_, uint256 clusterId) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.transferName(name_, clusterId);
        vm.stopPrank();
    }

    function testTransferNameRevertNoCluster(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.transferName(name_, 2);
    }

    function testTransferNameRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(Ownable.Unauthorized.selector);
        clusters.transferName(name_, 2);
        vm.stopPrank();
    }

    function testTransferNameRevertUnregistered(
        bytes32 callerSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 toClusterId
    ) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        vm.assume(toClusterId > 1);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.transferName(name_, toClusterId);
        vm.stopPrank();
    }

    /// pokeName() TESTS ///

    function testPokeName(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        timeSkew = bound(timeSkew, 1, 24 weeks - 1);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.warp(block.timestamp + timeSkew);
        vm.prank(addr);
        clusters.pokeName(name_);

        assertEq(clusters.addressToClusterId(callerBytes), 1, "address(this) not assigned to cluster");
        assertEq(clusters.nameToClusterId(name), 1, "name not assigned to cluster");
        assertFalse(buyAmount <= clusters.nameBacking(name), "nameBacking not adjusting");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testPokeNameRevertInvalidName(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.pokeName(name_);
        vm.stopPrank();
    }

    function testPokeNameRevertUnregistered(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.pokeName(name_);
        vm.stopPrank();
    }

    /// bidName() TESTS ///

    function testBidName(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(clusters.nameToClusterId(name), 1, "purchaser lost name after bid");
        assertEq(bid.ethAmount, bidAmount, "bid ethAmount incorrect");
        assertEq(bid.createdTimestamp, block.timestamp, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, addrBytes, "bid bidder incorrect");
        assertEq(address(clusters).balance, buyAmount + bidAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testBidNameIncreaseBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidIncrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        bidIncrease = bound(bidIncrease, 1, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount + bidIncrease);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);

        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, bidAmount, "bid ethAmount incorrect");
        assertEq(bid.createdTimestamp, block.timestamp, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, addrBytes, "bid bidder incorrect");
        assertEq(address(clusters).balance, buyAmount + bidAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );

        clusters.bidName{value: bidIncrease}(bidIncrease, name_);
        vm.stopPrank();

        bid = clusters.getBid(name);
        assertEq(bid.ethAmount, bidAmount + bidIncrease, "bid ethAmount incorrect");
        assertEq(bid.createdTimestamp, block.timestamp, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, addrBytes, "bid bidder incorrect");
        assertEq(address(clusters).balance, buyAmount + bidAmount + bidIncrease, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testBidNameOutbid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);
        vm.deal(PRANKED_ADDRESS, bidAmount + 1);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();
        uint256 balance = address(addr).balance;

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: bidAmount + 1}(bidAmount + 1, name_);
        vm.stopPrank();

        assertEq(address(addr).balance, balance + bidAmount, "_bidder1 balance error");
        assertEq(address(clusters).balance, buyAmount + bidAmount + 1, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, bidAmount + 1, "bid ethAmount incorrect");
        assertEq(bid.createdTimestamp, block.timestamp, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, _addressToBytes(PRANKED_ADDRESS), "bid bidder incorrect");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testBidNameRevertInvalidName(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, 0, 100 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.bidName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();
    }

    function testBidNameRevertNoCluster(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.bidName{value: bidAmount}(bidAmount, name_);
    }

    function testBidNameRevertNoBid(bytes32 callerSalt, bytes32 addrSalt, string memory name_, uint256 buyAmount)
        public
    {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.bidName{value: 0}(0, name_);
    }

    function testBidNameRevertUnregistered(bytes32 callerSalt, string memory name_, uint256 bidAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, bidAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.Unregistered.selector);
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();
    }

    function testBidNameRevertSelfBid(bytes32 callerSalt, string memory name_, uint256 buyAmount, uint256 bidAmount)
        public
    {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount + bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.expectRevert(IClusters.SelfBid.selector);
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();
    }

    function testBidNameRevertInsufficient(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 2, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, minPrice + 1);
        vm.deal(PRANKED_ADDRESS, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice - 1}(minPrice - 1, name_);
        vm.stopPrank();

        vm.startPrank(PRANKED_ADDRESS);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();

        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, bidAmount, "bid ethAmount incorrect");
        assertEq(bid.createdTimestamp, block.timestamp, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, _addressToBytes(PRANKED_ADDRESS), "bid bidder incorrect");
        assertEq(address(clusters).balance, buyAmount + bidAmount, "contract balance issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );

        vm.prank(addr);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.bidName{value: minPrice + 1}(minPrice + 1, name_);
    }

    /// reduceBid() TESTS ///

    function testReduceBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 1, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + 31 days);
        clusters.reduceBid(name_, bidDecrease);
        vm.stopPrank();

        assertEq(address(addr).balance, balance + bidDecrease, "bidder balance error");
        assertEq(address(clusters).balance, buyAmount + bidAmount - bidDecrease, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        // TODO: Update implementation once bid update timestamp handling is added
        assertEq(bid.createdTimestamp, block.timestamp - 31 days, "bid createdTimestamp incorrect");
        assertEq(bid.bidder, addrBytes, "bid bidder incorrect");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testReduceBidUint256Max(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        timeSkew = bound(timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + timeSkew);
        clusters.reduceBid(name_, type(uint256).max);
        vm.stopPrank();

        assertEq(address(addr).balance, balance + bidAmount, "bid refund balance error");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, 0, "bid ethAmount not purged");
        assertEq(bid.createdTimestamp, 0, "bid createdTimestamp not purged");
        assertEq(bid.bidder, _addressToBytes(address(0)), "bid bidder not purged");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testReduceBidTotalBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        timeSkew = bound(timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + timeSkew);
        clusters.reduceBid(name_, bidAmount);
        vm.stopPrank();

        assertEq(address(addr).balance, balance + bidAmount, "bid refund balance error");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        IClusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, 0, "bid ethAmount not purged");
        assertEq(bid.createdTimestamp, 0, "bid createdTimestamp not purged");
        assertEq(bid.bidder, _addressToBytes(address(0)), "bid bidder not purged");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testReduceBidExceedsBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        bidDecrease = bound(bidDecrease, bidAmount + 1, type(uint256).max);
        timeSkew = bound(timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        uint256 balance = address(addr).balance;

        vm.warp(block.timestamp + timeSkew);
        clusters.reduceBid(name_, bidDecrease);
        vm.stopPrank();

        assertEq(address(addr).balance, balance + bidAmount, "bid refund balance error");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        Clusters.Bid memory bid = clusters.getBid(name);
        assertEq(bid.ethAmount, 0, "bid ethAmount not purged");
        assertEq(bid.createdTimestamp, 0, "bid createdTimestamp not purged");
        assertEq(bid.bidder, _addressToBytes(address(0)), "bid bidder not purged");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testReduceBidRevertInvalidName(bytes32 callerSalt, string memory name_, uint256 bidDecrease) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.reduceBid(name_, bidDecrease);
        vm.stopPrank();
    }

    function testReduceBidRevertNoBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.reduceBid(name_, minPrice);
        vm.stopPrank();
    }

    function testReduceBidRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice + 1, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(Ownable.Unauthorized.selector);
        clusters.reduceBid(name_, bidDecrease);
    }

    function testReduceBidRevertTimelock(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice * 2, 10 ether);
        bidDecrease = bound(bidDecrease, 1, bidAmount - minPrice);
        timeSkew = bound(timeSkew, 1, 30 days - 1);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);

        vm.warp(block.timestamp + timeSkew);
        vm.expectRevert(IClusters.Timelock.selector);
        clusters.reduceBid(name_, bidDecrease);
        vm.stopPrank();
    }

    function testReduceBidRevertInsufficient(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount,
        uint256 bidDecrease,
        uint256 timeSkew
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice * 2, 10 ether);
        bidDecrease = bound(bidDecrease, bidAmount - minPrice + 1, bidAmount - 1);
        timeSkew = bound(timeSkew, 30 days + 1, 24 weeks);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);

        vm.warp(block.timestamp + timeSkew);
        vm.expectRevert(IClusters.Insufficient.selector);
        clusters.reduceBid(name_, bidDecrease);
        vm.stopPrank();
    }

    /// acceptBid() TESTS ///

    function testAcceptBid(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();

        uint256 balance = address(caller).balance;
        vm.prank(caller);
        clusters.acceptBid(name_);

        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 0, "names array not purged");
        names = clusters.getClusterNamesBytes32(2);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(clusters.nameToClusterId(name), 2, "name not assigned to cluster");
        assertEq(clusters.nameBacking(name), buyAmount, "ethBacking incorrect");
        assertEq(address(clusters).balance, buyAmount, "contract balance issue");
        assertEq(address(caller).balance, balance + bidAmount, "bid payment issue");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testAcceptBidRevertInvalidName(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length == 0 || bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);

        vm.startPrank(caller);
        clusters.create();
        if (bytes(name_).length == 0) {
            vm.expectRevert(IClusters.EmptyName.selector);
        } else {
            vm.expectRevert(IClusters.LongName.selector);
        }
        clusters.acceptBid(name_);
        vm.stopPrank();
    }

    function testAcceptBidRevertNoCluster(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.stopPrank();

        vm.prank(PRANKED_ADDRESS);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.acceptBid(name_);
    }

    function testAcceptBidRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount,
        uint256 bidAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        bidAmount = bound(bidAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);
        vm.deal(addr, bidAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        clusters.bidName{value: bidAmount}(bidAmount, name_);
        vm.expectRevert(Ownable.Unauthorized.selector);
        clusters.acceptBid(name_);
        vm.stopPrank();
    }

    function testAcceptBidRevertNoBid(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.expectRevert(IClusters.NoBid.selector);
        clusters.acceptBid(name_);
        vm.stopPrank();
    }

    /// CANONICAL AND WALLET NAME TESTS ///

    function testSetDefaultClusterName(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        clusters.setDefaultClusterName(name_);
        vm.stopPrank();

        assertEq(clusters.nameToClusterId(name), 1, "clusterId error");
        assertEq(clusters.defaultClusterName(1), name, "defaultClusterName error");
        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testSetDefaultClusterNameUpdate(
        bytes32 callerSalt,
        string memory name1,
        string memory name2,
        uint256 buyAmount
    ) public {
        vm.assume(bytes(name1).length > 0);
        vm.assume(bytes(name1).length <= 32);
        vm.assume(bytes(name2).length > 0);
        vm.assume(bytes(name2).length <= 32);
        vm.assume(keccak256(abi.encodePacked(name1)) != keccak256(abi.encodePacked(name2)));
        address caller = _bytesToAddress(callerSalt);
        bytes32 _name1 = _toBytes32(name1);
        bytes32 _name2 = _toBytes32(name2);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount * 2);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name1);
        clusters.buyName{value: buyAmount}(buyAmount, name2);
        clusters.setDefaultClusterName(name1);
        clusters.setDefaultClusterName(name2);
        vm.stopPrank();

        assertEq(clusters.nameToClusterId(_name1), 1, "clusterId error");
        assertEq(clusters.nameToClusterId(_name2), 1, "clusterId error");
        assertEq(clusters.defaultClusterName(1), _name2, "defaultClusterName error");
        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 2, "names array length error");
        assertEq(names[0], _name1, "name array error");
        assertEq(names[1], _name2, "name array error");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testSetDefaultClusterNameDelete(bytes32 callerSalt, string memory name_, uint256 buyAmount) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 name = _toBytes32(name_);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        clusters.setDefaultClusterName(name_);
        clusters.setDefaultClusterName("");
        vm.stopPrank();

        assertEq(clusters.nameToClusterId(name), 1, "clusterId error");
        assertEq(clusters.defaultClusterName(1), bytes32(""), "defaultClusterName error");
        bytes32[] memory names = clusters.getClusterNamesBytes32(1);
        assertEq(names.length, 1, "names array length error");
        assertEq(names[0], name, "name array error");
        assertEq(
            address(clusters).balance,
            clusters.protocolRevenue() + clusters.totalNameBacking() + clusters.totalBidBacking(),
            "invariant balance error"
        );
    }

    function testSetDefaultClusterNameRevertLongName(bytes32 callerSalt, string memory name_, uint256 buyAmount)
        public
    {
        vm.assume(bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.LongName.selector);
        clusters.setDefaultClusterName(name_);
        vm.stopPrank();
    }

    function testSetDefaultClusterNameRevertNoCluster(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.prank(addr);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.setDefaultClusterName(name_);
    }

    function testSetDefaultClusterNameRevertUnauthorized(
        bytes32 callerSalt,
        bytes32 addrSalt,
        string memory name_,
        uint256 buyAmount
    ) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        buyAmount = bound(buyAmount, minPrice, 10 ether);
        vm.deal(caller, buyAmount);

        clusters.openMarket();

        vm.startPrank(caller);
        clusters.create();
        clusters.buyName{value: buyAmount}(buyAmount, name_);
        vm.stopPrank();

        vm.startPrank(addr);
        clusters.create();
        vm.expectRevert(Ownable.Unauthorized.selector);
        clusters.setDefaultClusterName(name_);
        vm.stopPrank();
    }

    function testSetWalletName(bytes32 callerSalt, string memory name_) public {
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        bytes32 name = _toBytes32(name_);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(callerBytes, name_);
        vm.stopPrank();

        assertEq(clusters.addressToClusterId(callerBytes), 1, "addressToClusterId failed");
        assertEq(clusters.forwardLookup(1, name), callerBytes, "forwardLookup failed");
        assertEq(clusters.reverseLookup(callerBytes), name, "reverseLookup failed");

        // Set to new name
        name_ = "newtest";
        name = _toBytes32(name_);
        vm.startPrank(caller);
        clusters.setWalletName(callerBytes, name_);
        vm.stopPrank();

        assertEq(clusters.forwardLookup(1, name), callerBytes, "forwardLookup failed");
        assertEq(clusters.reverseLookup(callerBytes), name, "reverseLookup failed");
    }

    function testSetWalletNameOther(bytes32 callerSalt, bytes32 addrSalt, string memory name_) public {
        vm.assume(callerSalt != addrSalt);
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        address addr = _bytesToAddress(addrSalt);
        bytes32 addrBytes = _addressToBytes(addr);
        bytes32 name = _toBytes32(name_);

        vm.startPrank(caller);
        clusters.create();
        clusters.add(addrBytes);
        vm.stopPrank();

        vm.prank(addr);
        clusters.setWalletName(addrBytes, name_);

        assertEq(clusters.addressToClusterId(addrBytes), 1, "addressToClusterId failed");
        assertEq(clusters.forwardLookup(1, name), addrBytes, "forwardLookup failed");
        assertEq(clusters.reverseLookup(addrBytes), name, "reverseLookup failed");
    }

    function testSetWalletNameDelete(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);
        bytes32 name = _toBytes32(name_);

        vm.startPrank(caller);
        clusters.create();
        clusters.setWalletName(callerBytes, name_);
        clusters.setWalletName(callerBytes, "");
        vm.stopPrank();

        assertEq(clusters.addressToClusterId(callerBytes), 1, "clusterId error");
        assertEq(clusters.forwardLookup(1, name), _addressToBytes(address(0)), "forwardLookup not purged");
        assertEq(clusters.reverseLookup(callerBytes), bytes32(""), "reverseLookup not purged");
    }

    function testSetWalletNameRevertLongName(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length > 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);

        vm.startPrank(caller);
        clusters.create();
        vm.expectRevert(IClusters.LongName.selector);
        clusters.setWalletName(callerBytes, name_);
        vm.stopPrank();
    }

    function testSetWalletNameRevertNoCluster(bytes32 callerSalt, string memory name_) public {
        vm.assume(bytes(name_).length > 0 && bytes(name_).length <= 32);
        address caller = _bytesToAddress(callerSalt);
        bytes32 callerBytes = _addressToBytes(caller);

        vm.prank(caller);
        vm.expectRevert(IClusters.NoCluster.selector);
        clusters.setWalletName(callerBytes, name_);
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
