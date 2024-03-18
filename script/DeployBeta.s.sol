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

contract DeployBetaScript is Script {
    using OptionsBuilder for bytes;

    address constant lzTestnetEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f; // Same on all chains
    address constant lzProdEndpoint = 0x1a44076050125825900e736c501f859c50fE728c; // Same on all except shimmer/meter
    address constant proxyAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D; // Same for hub and initiator
    address constant refunderEoa = 0x443eDFF556D8fa8BfD69c3943D6eaf34B6a048e0;
    address constant grossprofitEoa = 0x4352Fb89eB97c3AeD354D4D003611C7a26BDc616;

    uint32 constant HOLESKY_EID = 40217;
    uint32 constant SEPOLIA_EID = 40161;
    uint32 constant ETHEREUM_EID = 30101;
    uint32 constant AVALANCHE_EID = 30106;
    uint32 constant POLYGON_EID = 30109;
    uint32 constant BINANCE_EID = 30102;
    uint32 constant OPTIMISM_EID = 30111;
    uint32 constant ARBITRUM_EID = 30110;
    uint32 constant BASE_EID = 30184;

    Singlesig constant sig = Singlesig(0x000000dE1E80ea5a234FB5488fee2584251BC7e8);
    ImmutableCreate2Factory constant factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);
    bytes initCode = type(BasicUUPSImpl).creationCode;
    bytes32 salt = 0x000000000000000000000000000000000000000097e5b90d2f1f6025db407f4d; // 0x19670000000A93f312163Cec8C4612Ae7a6783b4

    function _checkProxyExists(address addr) internal view returns (address implementationAddr) {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
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
        address implAddressCorrect = 0x19670000000A93f312163Cec8C4612Ae7a6783b4;
        // Sanity check logic contract exists
        // console2.logBytes32(UUPSUpgradeable(implAddress).proxiableUUID());
        // console2.log(implAddress);

        bytes memory proxyInitCode = LibClone.initCodeERC1967(implAddressCorrect);

        vm.startBroadcast();

        // bytes32 initCodeHash = keccak256(initCode);
        // console2.logBytes32(initCodeHash);

        address implAddress = factory.safeCreate2(salt, initCode);
        require(implAddress == implAddressCorrect, "wrong vanity logic addy");

        bytes32 proxyInitCodeHash = LibClone.initCodeHashERC1967(implAddressCorrect);
        // console2.logBytes32(proxyInitCodeHash);

        address proxyAddressDeployed =
            factory.safeCreate2(0x00000000000000000000000000000000000000001d210f3224b0fe09a30c6ddc, proxyInitCode);
        console2.log(proxyAddressDeployed);
        require(proxyAddress == proxyAddressDeployed, "wrong vanity proxy addy");

        vm.stopBroadcast();
    }

    /// @dev Precondition is that Singlesig and Proxy are already deployed
    /// @dev Then we deploy a new logic contract and upgrade the proxy to it
    /// @dev We call initialize separately bc initialization should only be done once, separating from upgradeToAndCall
    /// helps enforce this
    function upgradeHub() external {
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
        // ClustersBeta(proxyAddress).initialize(lzProdEndpoint, address(sig));
        ClustersBeta(proxyAddress).reinitialize();

        vm.stopBroadcast();
    }

    /// @dev Precondition is that Singlesig and Proxy are already deployed
    /// @dev Then we deploy a new logic contract and upgrade the proxy to it
    /// @dev We call initialize separately bc initialization should only be done once, separating from upgradeToAndCall
    /// helps enforce this
    function upgradeInitiator() external {
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
        InitiatorBeta(proxyAddress).initialize(lzProdEndpoint, address(sig));

        InitiatorBeta initiatorProxy = InitiatorBeta(proxyAddress);
        data = abi.encodeWithSelector(
            initiatorProxy.setPeer.selector, ETHEREUM_EID, bytes32(uint256(uint160(proxyAddress)))
        );
        sig.execute(proxyAddress, 0, data);

        data = abi.encodeWithSelector(initiatorProxy.setDstEid.selector, ETHEREUM_EID);
        sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }

    function configureHub() external {
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        bytes memory data =
            abi.encodeWithSelector(ClustersBeta(proxyAddress).withdraw.selector, grossprofitEoa, 0.0 ether);
        sig.execute(proxyAddress, 0, data);

        // ClustersBeta(proxyAddress).initialize(lzProdEndpoint, address(sig));

        // bytes memory data;
        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, AVALANCHE_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, POLYGON_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, BINANCE_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, OPTIMISM_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, ARBITRUM_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        // data = abi.encodeWithSelector(
        //     ClustersBeta(proxyAddress).setPeer.selector, BASE_EID, bytes32(uint256(uint160(proxyAddress)))
        // );
        // sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }

    function configureInitiator() external {
        console2.log(_checkProxyExists(proxyAddress));

        vm.startBroadcast();

        bytes memory data;
        InitiatorBeta initiatorProxy = InitiatorBeta(proxyAddress);
        data = abi.encodeWithSelector(
            initiatorProxy.setPeer.selector, ETHEREUM_EID, bytes32(uint256(uint160(proxyAddress)))
        );
        sig.execute(proxyAddress, 0, data);

        data = abi.encodeWithSelector(initiatorProxy.setDstEid.selector, ETHEREUM_EID);
        sig.execute(proxyAddress, 0, data);

        vm.stopBroadcast();
    }

    function doInitiate() external {
        console2.log(_checkProxyExists(proxyAddress));

        uint256 SIZE = 1;
        uint256[] memory amounts = new uint256[](SIZE);
        bytes32[] memory names = new bytes32[](SIZE);
        amounts[0] = 0.01 ether;
        names[0] = bytes32("testCrosschainPlural");

        InitiatorBeta initiatorProxy = InitiatorBeta(proxyAddress);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(99_000, 0.01 ether);
        // bytes memory message = abi.encodeWithSignature("placeBid(bytes32)", bytes32("testCrosschain"));
        bytes memory message = abi.encodeWithSignature("placeBids(uint256[],bytes32[])", amounts, names);
        uint256 nativeFee = initiatorProxy.quote(abi.encode(bytes32(uint256(uint160(msg.sender))), message), options);
        console2.log(nativeFee);
        console2.logBytes(message);

        vm.startBroadcast();

        // initiatorProxy.lzSend{value: nativeFee}(message, options);

        vm.stopBroadcast();
    }
}
