// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {EnumerableSetLib} from "clusters/libs/EnumerableSetLib.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";

contract EnumerableSetLibTest is Test {
    using EnumerableSetLib for *;
    using LibPRNG for *;

    EnumerableSetLib.Bytes32Set s;

    function testEnumerableSetBasic() public {
        assertEq(s.length(), 0);
        assertEq(s.contains(bytes32(uint256(1))), false);
        assertEq(s.contains(bytes32(uint256(2))), false);
        assertEq(s.contains(bytes32(uint256(3))), false);
        assertEq(s.contains(bytes32(uint256(4))), false);
        assertEq(s.contains(bytes32(uint256(5))), false);

        assertTrue(s.add(bytes32(uint256(1))));
        assertFalse(s.add(bytes32(uint256(1))));

        assertEq(s.length(), 1);
        assertEq(s.contains(bytes32(uint256(1))), true);
        assertEq(s.contains(bytes32(uint256(2))), false);
        assertEq(s.contains(bytes32(uint256(3))), false);
        assertEq(s.contains(bytes32(uint256(4))), false);
        assertEq(s.contains(bytes32(uint256(5))), false);

        assertTrue(s.add(bytes32(uint256(2))));
        assertFalse(s.add(bytes32(uint256(2))));

        assertEq(s.length(), 2);
        assertEq(s.contains(bytes32(uint256(1))), true);
        assertEq(s.contains(bytes32(uint256(2))), true);
        assertEq(s.contains(bytes32(uint256(3))), false);
        assertEq(s.contains(bytes32(uint256(4))), false);
        assertEq(s.contains(bytes32(uint256(5))), false);

        assertTrue(s.add(bytes32(uint256(3))));
        assertFalse(s.add(bytes32(uint256(3))));

        assertEq(s.length(), 3);
        assertEq(s.contains(bytes32(uint256(1))), true);
        assertEq(s.contains(bytes32(uint256(2))), true);
        assertEq(s.contains(bytes32(uint256(3))), true);
        assertEq(s.contains(bytes32(uint256(4))), false);
        assertEq(s.contains(bytes32(uint256(5))), false);

        assertTrue(s.add(bytes32(uint256(4))));
        assertFalse(s.add(bytes32(uint256(4))));

        assertEq(s.length(), 4);
        assertEq(s.contains(bytes32(uint256(1))), true);
        assertEq(s.contains(bytes32(uint256(2))), true);
        assertEq(s.contains(bytes32(uint256(3))), true);
        assertEq(s.contains(bytes32(uint256(4))), true);
        assertEq(s.contains(bytes32(uint256(5))), false);

        assertTrue(s.add(bytes32(uint256(5))));
        assertFalse(s.add(bytes32(uint256(5))));

        assertEq(s.length(), 5);
        assertEq(s.contains(bytes32(uint256(1))), true);
        assertEq(s.contains(bytes32(uint256(2))), true);
        assertEq(s.contains(bytes32(uint256(3))), true);
        assertEq(s.contains(bytes32(uint256(4))), true);
        assertEq(s.contains(bytes32(uint256(5))), true);
    }

    function testEnumerableSetBasic2() public {
        s.add(bytes32(uint256(1)));
        s.add(bytes32(uint256(2)));

        s.remove(bytes32(uint256(1)));
        assertEq(s.length(), 1);
        s.remove(bytes32(uint256(2)));
        assertEq(s.length(), 0);

        s.add(bytes32(uint256(1)));
        s.add(bytes32(uint256(2)));

        s.remove(bytes32(uint256(2)));
        assertEq(s.length(), 1);
        s.remove(bytes32(uint256(1)));
        assertEq(s.length(), 0);

        s.add(bytes32(uint256(1)));
        s.add(bytes32(uint256(2)));
        s.add(bytes32(uint256(3)));

        s.remove(bytes32(uint256(3)));
        assertEq(s.length(), 2);
        s.remove(bytes32(uint256(2)));
        assertEq(s.length(), 1);
        s.remove(bytes32(uint256(1)));
        assertEq(s.length(), 0);

        s.add(bytes32(uint256(1)));
        s.add(bytes32(uint256(2)));
        s.add(bytes32(uint256(3)));

        s.remove(bytes32(uint256(1)));
        assertEq(s.length(), 2);
        s.remove(bytes32(uint256(2)));
        assertEq(s.length(), 1);
        s.remove(bytes32(uint256(3)));
        assertEq(s.length(), 0);
    }

    function testEnumerableSetFuzz(uint256 n) public {
        unchecked {
            LibPRNG.PRNG memory prng;
            prng.state = n;
            uint256[] memory additions = new uint256[](prng.next() % 16);

            for (uint256 i; i != additions.length; ++i) {
                uint256 x = 1 | (prng.next() & 7);
                additions[i] = x;
                s.add(bytes32(x));
                assertTrue(s.contains(bytes32(x)));
            }
            LibSort.sort(additions);
            LibSort.uniquifySorted(additions);
            assertEq(s.length(), additions.length);
            {
                bytes32[] memory values = s.values();
                uint256[] memory valuesCasted = _toUints(values);
                LibSort.sort(valuesCasted);
                assertEq(valuesCasted, additions);
            }

            uint256[] memory removals = new uint256[](prng.next() % 16);
            for (uint256 i; i != removals.length; ++i) {
                uint256 x = 1 | (prng.next() & 7);
                removals[i] = x;
                s.remove(bytes32(x));
                assertFalse(s.contains(bytes32(x)));
            }
            LibSort.sort(removals);
            LibSort.uniquifySorted(removals);

            {
                uint256[] memory difference = LibSort.difference(additions, removals);
                bytes32[] memory values = s.values();
                uint256[] memory valuesCasted = _toUints(values);
                LibSort.sort(valuesCasted);
                assertEq(valuesCasted, difference);
            }
        }
    }

    function _toUints(bytes32[] memory a) private pure returns (uint256[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := a
        }
    }
}
