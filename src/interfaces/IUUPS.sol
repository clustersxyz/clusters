// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
