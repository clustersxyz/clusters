// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {toWadUnsafe, wadExp, wadLn, unsafeWadMul, unsafeWadDiv} from "solmate/utils/SignedWadMath.sol";

/// @notice Numerical approximation for principal branch of [Lambert W
/// function](https://en.wikipedia.org/wiki/Lambert_W_function)
/// @dev Only supports the [1/e, 3+1/e] and [3+1/e, inf] interval
/// @dev Approximate [1/e, 3+1/e] with a lookup table weighted average and [3+1/e, inf] with ln(x) + ln(ln(x)) +
/// ln(ln(x))/ln(x)
contract Lambert {
    int256 internal constant E_WAD = 2718281828459045235;
    int256 internal constant LOWER_BOUND_WAD = 367879441171442322; // 1/e
    int256 internal constant MID_BOUND_WAD = 3367879441171442322; // 3 + 1/e

    uint256 internal constant PRECISION_SLOTS = 128;
    uint256[129] internal lambertArray;

    constructor() {
        initLambertArray();
    }

    /// @notice Approximates W0(x) where x is a wad
    function W0(int256 xWad) external view returns (int256) {
        require(LOWER_BOUND <= xWad, "must be > 1/e");
        if (wadX <= MID_BOUND_WAD) {
            int256 range = MID_BOUND_WAD - LOWER_BOUND_WAD;
            // Use weighted average of lookup table
            // Slot number is slotCount * (x - a) / (b - a), we want integer rounding here
            uint256 slotIndex = (PRECISION_SLOTS * (xWad - LOWER_BOUND_WAD)) / range;
            int256 a = LOWER_BOUND_WAD + slotIndex * range / PRECISION_SLOTS;
            int256 b = a + range / PRECISION_SLOTS;
            // Weighted average is f(a) + w(f(b) - f(a)) = wf(b) + (1-w)f(a) where w = (x-a)/(b-a)
            int256 w = unsafeWadDiv(xWad - a, MID_BOUND_WAD);
            int256 result =
                unsafeWadMul(w, lambertArray[slotIndex + 1]) + unsafeWadMul(1e18 - w, lambertArray[slotIndex]);
            return result;
        } else {
            // Approximate
            int256 log = wadLn(wadX);
            int256 loglog = wadLn(log);
            return log + loglog + unsafeWadDiv(loglog, log);
        }
    }

    function initLambertArray() internal {}
}
