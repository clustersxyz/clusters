// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/ClustersNFTV1.sol";

contract MockClustersNFTV1 is ClustersNFTV1 {
    using DynamicArrayLib for *;

    NameData[2] internal _data;

    /// @dev Initializes the data.
    function _initialize(NameData storage data, uint256 id, uint256 ownedIndex) internal {
        if (ownedIndex <= 254) {
            data.packed = _setByte(id | (block.timestamp << 48), 26, 0xff ^ ownedIndex);
        } else {
            data.packed = id | (block.timestamp << 48);
            data.fullOwnedIndex = ownedIndex;
        }
    }

    /// @dev Returns the ID.
    function _getId(NameData storage data) internal view returns (uint40) {
        return uint40(data.packed);
    }

    /// @dev Returns the owned index.
    function _getOwnedIndex(NameData storage data) internal view returns (uint256) {
        uint256 ownedIndex = uint8(bytes32(data.packed)[26]);
        return ownedIndex != 0 ? 0xff ^ ownedIndex : data.fullOwnedIndex;
    }

    /// @dev Sets the owned index.
    function _setOwnedIndex(NameData storage data, uint256 ownedIndex) internal {
        if (ownedIndex <= 254) {
            data.packed = _setByte(data.packed, 26, 0xff ^ ownedIndex);
        } else {
            data.packed = _setByte(data.packed, 26, 0);
            data.fullOwnedIndex = ownedIndex;
        }
    }

    /// @dev Updates the start timestamp.
    function _updateStartTimestamp(NameData storage data) internal {
        uint256 p = data.packed;
        data.packed = p ^ (((p >> 48) ^ block.timestamp) & 0xffffffffff) << 48;
    }

    /// @dev Returns the start timestamp.
    function _getStartTimestamp(NameData storage data) internal view returns (uint256) {
        return (data.packed >> 48) & 0xffffffffff;
    }

    /// @dev Sets the additional data.
    function _setAdditionalData(NameData storage data, uint168 additionalData) internal {
        assembly ("memory-safe") {
            mstore(0x0b, sload(data.slot))
            mstore(0x00, additionalData)
            sstore(data.slot, mload(0x0b))
        }
    }

    /// @dev Returns the additional data.
    function _getAdditionalData(NameData storage data) internal view returns (uint168) {
        return uint168(data.packed >> 88);
    }

    function nameDataInitialize(uint256 i, uint40 id, uint256 ownedIndex) public {
        _initialize(_data[i], id, ownedIndex);
    }

    function nameDataGetId(uint256 i) public view returns (uint256) {
        return _getId(_data[i]);
    }

    function nameDataGetOwnedIndex(uint256 i) public view returns (uint256) {
        return _getOwnedIndex(_data[i]);
    }

    function nameDataSetOwnedIndex(uint256 i, uint256 ownedIndex) public {
        return _setOwnedIndex(_data[i], ownedIndex);
    }

    function nameDataSetAdditionalData(uint256 i, uint168 additionalData) public {
        return _setAdditionalData(_data[i], additionalData);
    }

    function nameDataGetAdditionalData(uint256 i) public view returns (uint168) {
        return _getAdditionalData(_data[i]);
    }
}
