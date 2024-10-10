// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/ClustersNFTV1.sol";

contract MockClustersNFTV1 is ClustersNFTV1 {
    using DynamicArrayLib for *;

    ClustersData[2] internal _data;

    function clustersDataInitialize(uint256 i, uint40 id, uint256 ownedIndex) public {
        _initialize(_data[i], id, ownedIndex);
    }

    function clustersDataGetId(uint256 i) public view returns (uint256) {
        return _getId(_data[i]);
    }

    function clustersDataGetOwnedIndex(uint256 i) public view returns (uint256) {
        return _getOwnedIndex(_data[i]);
    }

    function clustersDataSetOwnedIndex(uint256 i, uint256 ownedIndex) public {
        return _setOwnedIndex(_data[i], ownedIndex);
    }

    function clustersDataSetAdditionalData(uint256 i, uint208 additionalData) public {
        return _setAdditionalData(_data[i], additionalData);
    }

    function clustersDataGetAdditionalData(uint256 i) public view returns (uint208) {
        return _getAdditionalData(_data[i]);
    }
}
