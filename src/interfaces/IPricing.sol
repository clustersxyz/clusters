// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPricing {
    /// @notice The amount of eth that's been spent on a name since last update
    /// @param lastUpdatedPrice Can be greater than max price, used to calculate decay times
    /// @param secondsAfterUpdate How many seconds it's been since lastUpdatedPrice
    /// @return spent How much eth has been spent
    /// @return price The current un-truncated price, which can be greater than maxPrice
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsAfterUpdate)
        external
        view
        returns (uint256, uint256);

    function minAnnualPrice() external pure returns (uint256);
}
