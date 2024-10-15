// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "solady/tokens/ERC20.sol";

contract TestERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Test";
    }

    function symbol() public pure override returns (string memory) {
        return "TEST";
    }

    function mintHundredToSelf() public {
        _mint(msg.sender, 100 * 10 ** 18);
    }
}
