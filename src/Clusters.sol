// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Follow https://docs.soliditylang.org/en/latest/style-guide.html for style

import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {NameManager} from "./NameManager.sol";

import {IClusters} from "./IClusters.sol";

import {console2} from "../lib/forge-std/src/Test.sol";

/**
 * OPEN QUESTIONS/TODOS
 * Can you create a cluster without registering a name? No, there needs to be a bounty for adding others to your cluster
 * What does the empty foobar/ resolver point to?
 * If listings are offchain, then how can it hook into the onchain transfer function?
 * The first name added to a cluster should become the canonical name by default, every cluster should always have
 * canonical name
 */

contract Clusters is NameManager {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes4 internal constant BUY_NAME_SIG = bytes4(keccak256("buyName(uint256,string)"));
    bytes4 internal constant FUND_NAME_SIG = bytes4(keccak256("fundName(uint256,string)"));
    bytes4 internal constant BID_NAME_SIG = bytes4(keccak256("bidName(uint256,string)"));

    address public immutable endpoint;

    /// @dev Enumerate all addresses in a cluster
    mapping(uint256 clusterId => EnumerableSet.AddressSet addrs) internal _clusterAddresses;

    /// @notice Used to restrict external functions to
    modifier onlyEndpoint(address msgSender) {
        if (msg.sender != msgSender && msg.sender != endpoint) revert Unauthorized();
        _;
    }

    constructor(address pricing_, address endpoint_) NameManager(pricing_) {
        endpoint = endpoint_;
    }

    /// EXTERNAL FUNCTIONS ///

    function create() external {
        create(msg.sender);
    }

    function add(address addr) external {
        add(msg.sender, addr);
    }

    function remove(address addr) external {
        remove(msg.sender, addr);
    }

    function clusterAddresses(uint256 clusterId) external view returns (address[] memory) {
        return _clusterAddresses[clusterId].values();
    }

    /// PUBLIC FUNCTIONS ///

    function create(address msgSender) public onlyEndpoint(msgSender) {
        _add(msgSender, nextClusterId++);
    }

    function add(address msgSender, address addr) public onlyEndpoint(msgSender) {
        _checkZeroCluster(msgSender);
        if (addressToClusterId[addr] != 0) revert Registered();
        _add(addr, addressToClusterId[msgSender]);
    }

    function remove(address msgSender, address addr) public onlyEndpoint(msgSender) {
        _checkZeroCluster(msgSender);
        if (addressToClusterId[msgSender] != addressToClusterId[addr]) revert Unauthorized();
        _remove(addr);
    }

    /// MULTICALL FUNCTIONS ///

    /// @dev For payable multicall to be secure, we cannot trust msg.value params in other external methods
    /// @dev Must instead do strict protocol invariant checking at the end of methods like Uniswap V2
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        _inMulticall = true;
        uint256 totalValue;
        bool success;

        // Iterate through each call, check for payable functions' _value param, and tally up total value used
        for (uint256 i = 0; i < data.length; ++i) {
            // Retrieve each call's calldata looking for a _value parameter to ensure no double-spending
            uint256 callValue = _determineCallValue(data[i]);
            totalValue += callValue;

            // Execute each call
            //slither-disable-next-line calls-loop,delegatecall-loop
            (success, results[i]) = address(this).delegatecall(data[i]);
            if (!success) revert MulticallFailed();
        }
        if (totalValue > msg.value) revert Insufficient();

        // If caller overpaid, refund difference
        uint256 excessValue = msg.value - totalValue;
        if (excessValue > 0) {
            (success,) = payable(msg.sender).call{value: excessValue}("");
            if (!success) revert NativeTokenTransferFailed();
        }

        // Confirm contract balance invariant
        if (address(this).balance != protocolRevenue + totalNameBacking + totalBidBacking) revert Insolvent();
        _inMulticall = false;
    }

    function create(uint256) external payable onlyMulticall {
        create(msg.sender);
    }

    function add(uint256, address addr) external payable onlyMulticall {
        add(msg.sender, addr);
    }

    function remove(uint256, address addr) external payable onlyMulticall {
        remove(msg.sender, addr);
    }

    /// INTERNAL FUNCTIONS ///

    function _add(address addr, uint256 clusterId) internal {
        if (addressToClusterId[addr] != 0) revert Registered();
        addressToClusterId[addr] = clusterId;
        _clusterAddresses[clusterId].add(addr);
    }

    function _remove(address addr) internal {
        uint256 clusterId = addressToClusterId[addr];
        // If the cluster has valid names, prevent removing final address, regardless of what is supplied for addr
        if (_clusterNames[clusterId].length() > 0 && _clusterAddresses[clusterId].length() == 1) revert Invalid();
        delete addressToClusterId[addr];
        _clusterAddresses[clusterId].remove(addr);
        bytes32 walletName = reverseLookup[addr];
        if (walletName != bytes32("")) {
            delete forwardLookup[clusterId][walletName];
            delete reverseLookup[addr];
        }
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _determineCallValue(bytes calldata data) internal pure returns (uint256) {
        // Extract the function signature
        bytes4 sig = bytes4(data[:4]);

        // Match the function signature of a payable function
        if (sig == BUY_NAME_SIG || sig == FUND_NAME_SIG || sig == BID_NAME_SIG) {
            // Assume string parameter is always 32 bytes or less
            if (data.length != 132) revert Invalid();

            // Extract the value parameter
            console2.logBytes(data);
            uint256 value = abi.decode(data[4:], (uint256));
            console2.log(value);
            return value;
        }
        // Handle unmatched function signatures
        return 0;
    }
}
