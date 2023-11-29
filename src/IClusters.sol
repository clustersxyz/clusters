// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IClusters {
    function create() external;
    function add(address _addr) external;
    function remove(address _addr) external;
}