// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {BasicUUPSImpl} from "../src/BasicUUPSImpl.sol";
import {ClustersBeta} from "../src/ClustersBeta.sol";

interface Singlesig {
    function execute(address to, uint256 value, bytes memory data) external returns (bool success);
    function owner() external returns (address);
}

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

        // bytes32 initCodeHash = keccak256(initCode);
        // console2.logBytes32(initCodeHash);

        // address implAddress = factory.safeCreate2(salt, initCode);
        address implAddress = 0x19670000000A93f312163Cec8C4612Ae7a6783b4;
        console2.log(implAddress);

        // address proxyAddress = LibClone.deployERC1967(implAddress);
        bytes memory proxyInitCode = LibClone.initCodeERC1967(implAddress);
        bytes32 proxyInitCodeHash = LibClone.initCodeHashERC1967(implAddress);
        console2.logBytes32(proxyInitCodeHash);

        address proxyAddress = factory.safeCreate2(0x00000000000000000000000000000000000000001d210f3224b0fe09a30c6ddc, proxyInitCode);
        console2.log(proxyAddress);

        vm.stopBroadcast();
    }

    function deployAndUpgrade() external {
        Singlesig sig = Singlesig(0x000000dE1E80ea5a234FB5488fee2584251BC7e8);
        console2.log(sig.owner());

        vm.startBroadcast();

        address proxyAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);

        // ClustersBeta beta = new ClustersBeta();
        ClustersBeta beta = ClustersBeta(0xA22EE3E897d2Ce152410A6F178945e19816C7801);

        bytes memory data = abi.encodeWithSelector(proxy.upgradeToAndCall.selector, address(beta), "");
        console2.logBytes(data);

        sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }
}
