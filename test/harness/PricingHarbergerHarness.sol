// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PricingHarberger} from "clusters/PricingHarberger.sol";

contract PricingHarbergerHarness is PricingHarberger {
    constructor(uint256 _protocolDeployTimestamp) PricingHarberger(_protocolDeployTimestamp) {}

    /// EXPOSED INTERNAL FUNCTIONS ///

    function exposed_getMaxIntersection(uint256 p, uint256 yearsSinceDeploymentWad) public pure returns (uint256) {
        return getMaxIntersection(p, yearsSinceDeploymentWad);
    }

    function exposed_getMinIntersection(uint256 p) public pure returns (uint256) {
        return getMinIntersection(p);
    }

    function exposed_getIntegratedMaxPrice(uint256 numSeconds) public pure returns (uint256) {
        return getIntegratedMaxPrice(numSeconds);
    }

    function exposed_getMaxPrice(uint256 numSeconds) public pure returns (uint256) {
        return getMaxPrice(numSeconds);
    }

    function exposed_getIntegratedDecayPrice(uint256 p0, uint256 numSeconds) public pure returns (uint256) {
        return getIntegratedDecayPrice(p0, numSeconds);
    }

    function exposed_getDecayPrice(uint256 p0, uint256 numSeconds) public pure returns (uint256) {
        return getDecayPrice(p0, numSeconds);
    }

    function exposed_getDecayMultiplier(uint256 numSeconds) public pure returns (uint256) {
        return getDecayMultiplier(numSeconds);
    }

    function exposed_getPriceAfterBid(uint256 p0, uint256 pBid, uint256 bidLengthInSeconds)
        public
        pure
        returns (uint256)
    {
        return getPriceAfterBid(p0, pBid, bidLengthInSeconds);
    }
}
