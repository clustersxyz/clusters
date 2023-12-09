// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPricing} from "./interfaces/IPricing.sol";

contract PricingFlat is IPricing {
    uint256 public constant minAnnualPrice = 0.01 ether;

    /// @notice The amount of eth that's been spent on a name since last update
    /// @param lastUpdatedPrice Can be greater than max price, used to calculate decay times
    /// @param secondsAfterUpdate How many seconds it's been since lastUpdatedPrice
    /// @return spent How much eth has been spent
    /// @return price The current un-truncated price, which can be greater than maxPrice
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsAfterUpdate, uint256 secondsAfterCreation)
        public
        pure
        returns (uint256 spent, uint256 price)
    {
        spent = secondsAfterUpdate * minAnnualPrice / 365 days;
        price = minAnnualPrice;
    }
}
