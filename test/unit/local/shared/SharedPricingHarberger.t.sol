// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../../Base.t.sol";

abstract contract PricingHarberger_Unit_Shared_Test is Base_Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment();
        endpointProxy = IEndpoint(endpointGroup.at(0));
    }
}
