// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test} from "../../../Base.t.sol";

abstract contract PricingHarberger_Unit_Shared_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(1);
    }
}
