// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/ClustersMarketV1.sol";

contract MockClustersMarketV1 is ClustersMarketV1 {
    function getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsSinceUpdate)
        public
        view
        returns (uint256 spent, uint256 price)
    {
        return _getIntegratedPrice(_getClustersMarketStorage().contracts, lastUpdatedPrice, secondsSinceUpdate);
    }

    function minAnnualPrice() public view returns (uint256) {
        return _minAnnualPrice(_getClustersMarketStorage().contracts);
    }

    function directMove(bytes32 clusterName, address to) public {
        uint256 contracts = _getClustersMarketStorage().contracts;
        uint256 packedInfo = _packedInfo(contracts, clusterName);
        _move(contracts, to, packedInfo);
    }
}
