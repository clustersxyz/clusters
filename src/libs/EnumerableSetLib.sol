// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library EnumerableSetLib {
    error ValueCannotBeZero();

    struct Bytes32 {
        bytes32 value;
    }

    struct Uint256 {
        uint256 value;
    }

    struct Bytes32Set {
        mapping(uint256 => Bytes32) _values;
        mapping(bytes32 => Uint256) _positions;
        uint256 _length;
    }

    function length(Bytes32Set storage set) internal view returns (uint256) {
        uint256 n = set._length;
        if (n == 0) {
            if (set._values[0].value == bytes32(0)) return 0;
            if (set._values[1].value == bytes32(0)) return 1;
            if (set._values[2].value == bytes32(0)) return 2;
            return 3;
        }
        return uint256(uint248(n));
    }

    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        if (value == bytes32(0)) revert ValueCannotBeZero();

        if (set._length == 0) {
            if (set._values[0].value == value) return true;
            if (set._values[1].value == value) return true;
            if (set._values[2].value == value) return true;
            return false;
        }
        return set._positions[value].value != 0;
    }

    function add(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        if (value == bytes32(0)) revert ValueCannotBeZero();
        uint256 n = set._length;
        if (n == 0) {
            Bytes32 storage p0 = set._values[0];
            bytes32 v0 = p0.value;
            if (v0 == bytes32(0)) {
                p0.value = value;
                return true;
            } else if (v0 == value) {
                return false;
            }
            Bytes32 storage p1 = set._values[1];
            bytes32 v1 = p1.value;
            if (v1 == bytes32(0)) {
                p1.value = value;
                return true;
            } else if (v1 == value) {
                return false;
            }
            Bytes32 storage p2 = set._values[2];
            bytes32 v2 = p2.value;
            if (v2 == bytes32(0)) {
                p2.value = value;
                set._positions[v0].value = 1;
                set._positions[v1].value = 2;
                set._positions[value].value = 3;
                set._length = 3 | (1 << 255);
                return true;
            } else if (v2 == value) {
                return false;
            }
        }
        Uint256 storage q = set._positions[value];
        uint256 i = q.value;
        if (i == 0) {
            set._values[uint256(uint248(n))].value = value;
            unchecked {
                n += 1;
            }
            q.value = uint256(uint248(n));
            set._length = n;
            return true;
        }
    }

    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool result) {
        if (value == bytes32(0)) revert ValueCannotBeZero();

        unchecked {
            uint256 n = set._length;
            if (n == 0) {
                Bytes32 storage p0 = set._values[0];
                bytes32 v0 = p0.value;
                Bytes32 storage p1 = set._values[1];
                if (v0 == bytes32(0)) {
                    return false;
                } else if (v0 == value) {
                    p0.value = p1.value;
                    p1.value = bytes32(0);
                    return true;
                }
                bytes32 v1 = p1.value;
                if (v1 == bytes32(0)) {
                    return false;
                } else if (v1 == value) {
                    p1.value = bytes32(0);
                    return true;
                }
                return false;
            }

            Uint256 storage p = set._positions[value];
            uint256 position = p.value;
            if (position == 0) {
                return false;
            }
            uint256 valueIndex = position - 1;
            uint256 j = n - 1;
            uint256 lastIndex = uint256(uint248(j));
            Bytes32 storage last = set._values[lastIndex];
            if (valueIndex != lastIndex) {
                bytes32 lastValue = last.value;
                set._values[valueIndex].value = lastValue;
                last.value = bytes32(0);
                set._positions[lastValue].value = position;
            }
            set._length = j;
            p.value = 0;
            return true;
        }
    }

    function values(Bytes32Set storage set) internal view returns (bytes32[] memory result) {
        unchecked {
            uint256 n = length(set);
            result = new bytes32[](n);
            for (uint256 i; i != n; ++i) {
                result[i] = set._values[i].value;
            }
        }
    }

    function at(Bytes32Set storage set, uint256 i) internal view returns (bytes32) {
        return set._values[i].value;
    }
}
