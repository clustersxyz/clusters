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
import {MessageHubLibV1 as MessageHubLib} from "clusters/MessageHubLibV1.sol";

/// @title ClustersMarketV1
/// @notice All prices are in Ether.
contract ClustersMarketV1 is UUPSUpgradeable, Initializable, Ownable {
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
        // The stateless pricing contract and NFT contract. Packed.
        // They both have at least 4 leading zero bytes. Let's save a SLOAD.
        // Bits Layout:
        // - [0..127]   `pricing`.
        // - [128..255] `nft`.
        uint256 contracts;
        // Mapping of `clusterName` to `bid`.
        mapping(bytes32 => Bid) bids;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersMarketStorage() internal pure returns (ClustersMarketStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersMarketStorage")))`.
            $.slot := 0xda8b89020ecb842518 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 CONTRACT INTERNAL HELPERS                  */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    // Note:
    // - `info` is an uint256 that contains the NFT `id` along with it's owner.
    //   Bits Layout:
    //   - [0..39]   `id`.
    //   - [96..255] `owner`.
    // - `contracts` is a uint256 that contains both the pricing contract and NFT contract.
    //   By passing around packed variables, we save gas on stack ops and avoid stack-too-deep.

    function _info(uint256 contracts, bytes32 clusterName) internal view returns (uint256 result) {}

    function _register(uint256 contracts, bytes32 clusterName, address to, uint256 info) internal {
        // If not available, revert.
        // If `info == 0`, `_mintNext`.
        // Else, `info` is `id`. Move from `(id & 0xff) + 1` to `to`.
    }

    function _unregister(uint256 contracts, bytes32 clusterName, uint256 info) internal {
        // If available, revert.
        // `info` is `id`. Force move to `(id & 0xff) + 1`
    }

    function _move(uint256 contracts, bytes32 clusterName, address to, uint256 info) internal {}

    function _minAnnualPrice(uint256 contracts) internal view returns (uint256 result) {}

    function _getIntegratedPrice(uint256 contracts, uint256 lastUpdatedPrice, uint256 secondsSinceUpdate)
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
