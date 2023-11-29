// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./INameManager.sol";

interface IClusters is INameManager {
    /// ERRORS ///

    error MulticallFailed();

    /// STORAGE / VIEW FUNCTIONS ///

    function clusterAddresses(uint256 _clusterId) external view returns (address[] memory addresses);

    /// EXTERNAL FUNCTIONS ///

    function create() external;
    function add(address _addr) external;
    function remove(address _addr) external;
    function leave() external;
}