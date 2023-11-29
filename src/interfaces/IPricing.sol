// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPricing {
    /// STORAGE / VIEW FUNCTIONS ///

    function minAnnualPrice() external view returns (uint256 minPrice);
    function maxPriceBase() external view returns (uint256 priceBase);
    function maxPriceIncrement() external view returns (uint256 priceIncrement);
    function getMaxDuration(uint256 _p0, uint256 _ethAmount) external view returns (int256 maxDuration);
    function getIntegratedPrice(uint256 _lastUpdatedPrice, uint256 _secondsAfterUpdate, uint256 _secondsAfterCreation) external view returns (uint256 spent, uint256 price);
    function getIntegratedMaxPrice(uint256 _numSeconds) external view returns (uint256 integratedMaxPrice);
    function getMaxPrice(uint256 _numSeconds) external view returns (uint256 maxPrice);
    function getIntegratedDecayPrice(uint256 _p0, uint256 _numSeconds) external pure returns (uint256 integratedDecayPrice);
    function getDecayPrice(uint256 _p0, uint256 _numSeconds) external pure returns (uint256 decayPrice);
    function getDecayMultiplier(uint256 _numSeconds) external pure returns (int256 decayMultiplier);
    function getPriceAfterBid(uint256 _p0, uint256 _pBid, uint256 _bidLengthInSeconds) external pure returns (uint256 price);
}