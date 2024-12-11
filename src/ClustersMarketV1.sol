// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibMap} from "solady/utils/LibMap.sol";
import {LibBit} from "solady/utils/LibBit.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {MessageHubLibV1 as MessageHubLib} from "clusters/MessageHubLibV1.sol";

/// @title ClustersMarketV1
/// @notice All prices are in Ether.
contract ClustersMarketV1 is UUPSUpgradeable, Initializable, Ownable, EnumerableRoles {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The storage struct for a bid.
    struct Bid {
        // Price integral last price.
        uint88 integratedPrice;
        // Price integral last update timestamp.
        uint40 integratedUpdated;
        // Bid amount.
        uint88 bidAmount;
        // Bid last update timestamp.
        uint40 bidUpdated;
        // Bidder.
        address bidder;
        // Amount backing the name.
        uint88 backing;
    }

    /// @dev The storage struct for the contract.
    struct ClustersMarketStorage {
        // Stateless pricing contract.
        address pricing;
        // Clusters NFT contract.
        address nft;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersMarketStorage() internal pure returns (ClustersMarketStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersMarketStorage")))`.
            $.slot := 0xda8b89020ecb842518 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    function _availability(bytes32 clustersName) public view returns (uint256 result) {
        // Query `infoOf`. If `id` is zero, return 0.
        // Else if `owner` is `1..256`, return id.
        // Else return `_UNAVAILABLE`.
    }

    function _register(bytes32 clustersName, address to, uint256 availability) internal {
        // If not available, revert.
        // If `availability == 0`, `_mintNext`.
        // Else, `availability` is `id`. Move from `(id & 0xff) + 1` to `to`.
    }

    function _unregister(bytes32 clustersName, uint256 availability) internal {
        // If available, revert.
        // `availability` is `id`. Force move to `(id & 0xff) + 1`
    }

    function _move(bytes32 clustersName, address to, uint256 availability) internal {}

    function _minAnnualPrice() internal view returns (uint256) {}

    function _getIntegratedPrice(uint256 lastUpdatedPrice, uint256 secondsSinceUpdate)
        internal
        view
        returns (uint256 spent, uint256 price)
    {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
