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
        uint88 integralPrice;
        // Price integral last updated.
        uint40 integralUpdated;
        // The bid amount.
        uint88 bidAmount;
        // The bid updated timestamp.
        uint40 bidUpdated;
        // The bidder.
        address bidder;
        // The amount backing the name.
        uint88 backing;
    }

    /// @dev The storage struct for the contract.
    struct ClustersMarketStorage {
        // The address of the current pricing contract.
        address pricing;
        // The address of the Clusters NFT contract.
        address nft;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersMarketStorage() internal pure returns (ClustersMarketStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersMarketStorage")))`.
            $.slot := 0xda8b89020ecb842518 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    function isAvailable(bytes32 clustersName) public view returns (bool result) {
        // Query `infoOf`. If `id` is zero, or if `owner` is `address(this)`, return true.
        // Else return false.
    }

    function _register(bytes32 clustersName, address to) internal {}

    function _deregister(bytes32 clustersName) internal {}

    function _move(bytes32 clustersName, address to) internal {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
