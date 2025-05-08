// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {LibMulticaller} from "multicaller/LibMulticaller.sol";

/// @title MessageHubLibV1
/// @notice Library for returning the `senderOrSigner`.
library MessageHubLibV1 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The canonical address of the address hub.
    address internal constant MESSAGE_HUB = address(123456);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OPERATIONS                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the sender or signer.
    /// Note: this function will never return a zero address.
    function senderOrSigner() internal view returns (address result) {
        result = LibMulticaller.senderOrSigner();
        if (result == MESSAGE_HUB) {
            assembly ("memory-safe") {
                if and(gt(returndatasize(), 0x1f), staticcall(gas(), result, 0x00, 0x00, 0x00, 0x20)) {
                    result := mload(0x00)
                }
            }
        }
    }
}
