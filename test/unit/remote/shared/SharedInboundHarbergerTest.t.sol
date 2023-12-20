// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test} from "../../../Base.t.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Inbound_Harberger_Shared_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(2);
    }
}
