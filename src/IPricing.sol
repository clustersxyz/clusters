// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPricing {
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsAfterUpdate, uint256 secondsAfterCreation)
        external
        pure
        returns (uint256, uint256);

    function minAnnualPrice() external pure returns (uint256);
}
