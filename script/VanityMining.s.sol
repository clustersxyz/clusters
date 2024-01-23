// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {BasicUUPSImpl} from "../src/BasicUUPSImpl.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
    function findCreate2Address(bytes32 salt, bytes calldata initCode)
        external
        view
        returns (address deploymentAddress);
    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address deploymentAddress);
}

contract VanityMining is Script {
    ImmutableCreate2Factory immutable factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);
    bytes initCode = type(BasicUUPSImpl).creationCode;
    bytes32 salt = 0x000000000000000000000000000000000000000097e5b90d2f1f6025db407f4d; // 0x19670000000A93f312163Cec8C4612Ae7a6783b4

    function run() external {
        vm.startBroadcast();

        bytes32 initCodeHash = keccak256(initCode);
        console2.logBytes32(initCodeHash);

        // address implAddress = factory.safeCreate2(salt, initCode);
        address implAddress = 0x19670000000A93f312163Cec8C4612Ae7a6783b4;
        console2.log(implAddress);

        address proxyAddress = LibClone.deployERC1967(implAddress);
        console2.log(proxyAddress);



        vm.stopBroadcast();
    }
}
