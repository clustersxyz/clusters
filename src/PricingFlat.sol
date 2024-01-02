// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IPricing, IPricingFlat} from "./interfaces/IPricingFlat.sol";

contract PricingFlat is UUPSUpgradeable, Initializable, Ownable, IPricingFlat {
    uint256 public constant minAnnualPrice = 0.01 ether;

    function initialize(address owner_) public initializer {
        _initializeOwner(owner_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
