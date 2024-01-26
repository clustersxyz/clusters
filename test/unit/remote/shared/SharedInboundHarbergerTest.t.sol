// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base_Test, ClustersHub, Endpoint, OAppUpgradeable, EnumerableSet, console2} from "../../../Base.t.sol";
//import {@layerzerolabs/lz-evm-protocol-v2/

abstract contract Inbound_Harberger_Shared_Test is Base_Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    Endpoint internal localEndpoint;
    Endpoint internal remoteEndpoint;
    ClustersHub internal localClusters;

    function setUp() public virtual override {
        Base_Test.setUp();
        configureHarbergerEnvironment(2);
        localEndpoint = Endpoint(endpointGroup.at(0));
        remoteEndpoint = Endpoint(endpointGroup.at(1));
        localClusters = ClustersHub(clustersGroup.at(0));
        console2.log("localClusters address:");
        console2.log(address(localClusters));
        console2.log("");
        console2.log("localEndpoint address:");
        console2.log(address(localEndpoint));
        console2.log("localEndpoint's LZ Endpoint:");
        console2.log(address(OAppUpgradeable(localEndpoint).endpoint()));
        console2.log("localEndpoint's LZ EID:");
        console2.log((OAppUpgradeable(localEndpoint).endpoint()).eid());
        console2.log("localEndpoint's DstEid: (will be 0 as it doesn't send to a destination yet)");
        console2.log(localEndpoint.dstEid());
        console2.log("");
        console2.log("remoteEndpoint address:");
        console2.log(address(remoteEndpoint));
        console2.log("remoteEndpoint's LZ Endpoint:");
        console2.log(address(OAppUpgradeable(remoteEndpoint).endpoint()));
        console2.log("remoteEndpoint's LZ EID:");
        console2.log((OAppUpgradeable(remoteEndpoint).endpoint()).eid());
        console2.log("remoteEndpoint's DstEid:");
        console2.log(remoteEndpoint.dstEid());
    }
}
