// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPricing} from "./interfaces/IPricing.sol";

contract PricingFlat is IPricing {
    uint256 public constant minAnnualPrice = 0.01 ether;

    /// @inheritdoc IPricing
    function getIntegratedPrice(uint256, uint256 secondsSinceUpdate)
        public
        pure
        returns (uint256 spent, uint256 price)
    {
        spent = secondsSinceUpdate * minAnnualPrice / 365 days;
        price = minAnnualPrice;
    }
}
