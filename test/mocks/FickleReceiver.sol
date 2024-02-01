// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract FickleReceiver {
    error NotReceiving();

    bool isReceiving = true;

    constructor() {}

    function toggle() external {
        isReceiving = !isReceiving;
    }

    function execute(address to, uint256 value, bytes memory data)
        external
        returns (bool success, bytes memory result)
    {
        (success, result) = to.call{value: value}(data);
        if (!success) {
            if (result.length > 0) {
                assembly {
                    let result_size := mload(result)
                    revert(add(32, result), result_size)
                }
            } else {
                revert("External call failed without revert reason");
            }
        }
    }

    receive() external payable {
        if (!isReceiving) revert NotReceiving();
    }

    fallback() external payable {
        if (!isReceiving) revert NotReceiving();
    }
}
