// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPricing} from "./IPricing.sol";

interface IPricingFlat is IPricing {
    /// @dev Used to initialize the contract as it is used via an ERC1967Proxy
    function initialize(address owner_) external;
}
