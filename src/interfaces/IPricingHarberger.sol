// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPricing} from "./IPricing.sol";

interface IPricingHarberger is IPricing {
    /// @dev Used to initialize the contract as it is used via an ERC1967Proxy
    function initialize(address owner_, uint256 protocolDeployTimestamp_) external;
}
