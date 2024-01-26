// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {BasicUUPSImpl} from "../src/BasicUUPSImpl.sol";
import {ClustersBeta} from "../src/ClustersBeta.sol";
import {InitiatorBeta} from "../src/InitiatorBeta.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";


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
    using OptionsBuilder for bytes;

    address constant lzTestnetEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f; // Same on all chains
    address constant proxyAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D; // Same for hub and initiator

    uint32 constant HOLESKY_EID = 40217;
    uint32 constant SEPOLIA_EID = 40161;

    Singlesig constant sig = Singlesig(0x000000dE1E80ea5a234FB5488fee2584251BC7e8);
    ImmutableCreate2Factory constant factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);
    bytes initCode = type(BasicUUPSImpl).creationCode;
    bytes32 salt = 0x000000000000000000000000000000000000000097e5b90d2f1f6025db407f4d; // 0x19670000000A93f312163Cec8C4612Ae7a6783b4

    function _checkProxyExists(address addr) internal view returns (address implementationAddr) {
        bytes32 implSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        bytes32 proxySlot = vm.load(proxyAddress, implSlot);
        address implAddr;
        assembly {
            mstore(0, proxySlot)
            implAddr := mload(0)
        }    
        require(implAddr != address(0), "proxy not deployed"); 
        return implAddr;
    }

    /// @dev Deploy a dummy logic contract and vanity address proxy contract
    function deployVanityProxy() external {
        address implAddress = 0x19670000000A93f312163Cec8C4612Ae7a6783b4;
        // address implAddress = 0x19670000000A93f312163CEC8C4612Ae7a6783B5;
        // Sanity check logic contract exists
        console2.logBytes32(UUPSUpgradeable(implAddress).proxiableUUID());
        console2.log(implAddress);

        bytes memory proxyInitCode = LibClone.initCodeERC1967(implAddress);

        vm.startBroadcast();

        // bytes32 initCodeHash = keccak256(initCode);
        // console2.logBytes32(initCodeHash);

        // address implAddress = factory.safeCreate2(salt, initCode);


        // bytes32 proxyInitCodeHash = LibClone.initCodeHashERC1967(implAddress);
        // console2.logBytes32(proxyInitCodeHash);

        // address proxyAddress =
        //     factory.safeCreate2(0x00000000000000000000000000000000000000001d210f3224b0fe09a30c6ddc, proxyInitCode);
        // console2.log(proxyAddress);

        vm.stopBroadcast();
    }

    /// @dev Precondition is that Singlesig and Proxy are already deployed
    /// @dev Then we deploy a new logic contract and upgrade the proxy to it
    /// @dev We call initialize separately bc initialization should only be done once, separating from upgradeToAndCall helps enforce this
    function deployHub() external {
        // Sanity check singlesig exists
        console2.log(sig.owner());

        // Sanity check proxy exists
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        ClustersBeta logic = new ClustersBeta();
        console2.log(address(logic));
        bytes memory data = abi.encodeWithSelector(proxy.upgradeToAndCall.selector, address(logic), "");
        sig.execute(proxyAddress, 0, data);
        ClustersBeta(proxyAddress).initialize(lzTestnetEndpoint, address(sig));

        vm.stopBroadcast();
    }

    /// @dev Precondition is that Singlesig and Proxy are already deployed
    /// @dev Then we deploy a new logic contract and upgrade the proxy to it
    /// @dev We call initialize separately bc initialization should only be done once, separating from upgradeToAndCall helps enforce this
    function deployInitiator() external {
        // Sanity check singlesig exists
        console2.log(sig.owner());

        // Sanity check proxy exists
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        InitiatorBeta logic = new InitiatorBeta();
        console2.log(address(logic));
        bytes memory data = abi.encodeWithSelector(proxy.upgradeToAndCall.selector, address(logic), "");
        sig.execute(proxyAddress, 0, data);
        InitiatorBeta(proxyAddress).initialize(lzTestnetEndpoint, address(sig));

        vm.stopBroadcast();
    }

    function configureHub() external {
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        bytes memory data = abi.encodeWithSelector(ClustersBeta(proxyAddress).setPeer.selector, HOLESKY_EID, bytes32(uint256(uint160(proxyAddress))));
        sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }

    function configureInitiator() external {
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        bytes memory data;
        InitiatorBeta initiatorProxy = InitiatorBeta(proxyAddress);
        data = abi.encodeWithSelector(initiatorProxy.setPeer.selector, SEPOLIA_EID, bytes32(uint256(uint160(proxyAddress))));
        sig.execute(proxyAddress, 0, data);
        
        data = abi.encodeWithSelector(initiatorProxy.setDstEid.selector, SEPOLIA_EID);
        sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }

    function testInitiate() external {
        console2.log(_checkProxyExists(proxyAddress));

        InitiatorBeta initiatorProxy = InitiatorBeta(proxyAddress);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(99_000, 0.1 ether);
        bytes memory message = abi.encodeWithSignature("placeBid(bytes32)", "testCrosschain");
        uint256 nativeFee = initiatorProxy.quote(message, options);
        console2.log(nativeFee);

        vm.startBroadcast();

        initiatorProxy.lzSend{value: nativeFee}(message, options);

        vm.stopBroadcast();
    }
}
