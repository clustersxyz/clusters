// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test, EnumerableSet, Endpoint} from "../../../Base.t.sol";

abstract contract Inbound_Harberger_Shared_Test is Base_Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    Endpoint internal localEndpoint;
    Endpoint internal remoteEndpoint;

    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(2);
        localEndpoint = Endpoint(endpointGroup.at(0));
        remoteEndpoint = Endpoint(endpointGroup.at(1));
    }
}
