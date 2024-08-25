// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Used for setting an explicit DVN config when no default DVN exists (like on Blast)
interface IEndpointContract {
    struct SetConfigParam {
        uint32 dstEid;
        uint32 configType;
        bytes config;
    }

    struct UlnConfig {
        uint64 confirmations;
        uint8 requiredDVNCount;
        uint8 optionalDVNCount;
        uint8 optionalDVNThreshold;
        address[] requiredDVNs;
        address[] optionalDVNs;
    }

    struct ExecutorConfig {
        uint32 maxMessageSize;
        address executorAddress;
    }

    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
}

interface Singlesig {
    function execute(address to, uint256 value, bytes memory data) external returns (bool success);
    function owner() external returns (address);
}

contract SetConfigScript is Script {
    // MAKE SURE ALL FOLLOWING VALUES ARE UP TO DATE
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses

    // LayerZero does not set default DVNs on pathways with only 1 DVN, must configure manually (aka Blast)
    // getUlnConfig() on the SendUln302 contract is where you can see if the default exists
    // Must be configured on both source and destination chain

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    string originRpcUrl = "https://rpc.taiko.xyz";
    address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    address originEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address originSendLib = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;
    address originReceiveLib = 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    address originExecutor = 0xa20DB4Ffe74A31D17fc24BD32a7DD7555441058e;
    address originDVN = 0x88B27057A9e00c5F05DDa29241027afF63f9e6e0;
    uint32 originEid = 30290;

    string destRpcUrl = "https://eth.llamarpc.com";
    address destOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    address destEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address destSendLib = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address destReceiveLib = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    address destExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    address destDVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    uint32 destEid = 30101;

    uint32 maxMessageSize = 16384;
    uint64 confirmations = 5;
    uint8 requiredDVNCount = 1;
    uint8 optionalDVNCount = 0;
    uint8 optionalDVNThreshold = 0;

    Singlesig constant sig = Singlesig(0x000000dE1E80ea5a234FB5488fee2584251BC7e8);

    function setOriginSendConfig() public {
        IEndpointContract endpointContract = IEndpointContract(originEndpoint);

        // ULN Configuration
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = originDVN;
        address[] memory optionalDVNs = new address[](0);
        bytes memory ulnConfig = abi.encode(
            IEndpointContract.UlnConfig(
                confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
            )
        );

        // Executor Configuration
        bytes memory executorConfig = abi.encode(IEndpointContract.ExecutorConfig(maxMessageSize, originExecutor));

        IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](2);
        params[0] = IEndpointContract.SetConfigParam({dstEid: destEid, configType: 2, config: ulnConfig});
        params[1] = IEndpointContract.SetConfigParam({dstEid: destEid, configType: 1, config: executorConfig});

        vm.createSelectFork(originRpcUrl);
        vm.startBroadcast(deployerPrivateKey);
        bytes memory data =
            abi.encodeWithSelector(endpointContract.setConfig.selector, originOAppAddress, originSendLib, params);
        sig.execute(address(endpointContract), 0, data);
        // endpointContract.setConfig(originOAppAddress, originSendLib, params);
        vm.stopBroadcast();
    }

    function setOriginReceiveConfig() public {
        IEndpointContract endpointContract = IEndpointContract(originEndpoint);

        // ULN Configuration
        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = originDVN;
        address[] memory optionalDVNs = new address[](0);
        bytes memory ulnConfig = abi.encode(
            confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
        );

        IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](2);
        params[0] = IEndpointContract.SetConfigParam({dstEid: destEid, configType: 2, config: ulnConfig});

        vm.createSelectFork(originRpcUrl);
        vm.startBroadcast(deployerPrivateKey);
        endpointContract.setConfig(originOAppAddress, originReceiveLib, params);
        vm.stopBroadcast();
    }

    function setDestSendConfig() public {
        IEndpointContract endpointContract = IEndpointContract(destEndpoint);

        // ULN Configuration
        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = destDVN;
        address[] memory optionalDVNs = new address[](0);
        bytes memory ulnConfig = abi.encode(
            confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
        );

        // Executor Configuration
        bytes memory executorConfig = abi.encode(maxMessageSize, destExecutor);

        IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](2);
        params[0] = IEndpointContract.SetConfigParam({dstEid: originEid, configType: 2, config: ulnConfig});
        params[1] = IEndpointContract.SetConfigParam({dstEid: originEid, configType: 1, config: executorConfig});

        vm.createSelectFork(destRpcUrl);
        vm.startBroadcast(deployerPrivateKey);
        endpointContract.setConfig(destOAppAddress, destSendLib, params);
        vm.stopBroadcast();
    }

    function setDestReceiveConfig() public {
        IEndpointContract endpointContract = IEndpointContract(destEndpoint);

        // ULN Configuration
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = destDVN;
        address[] memory optionalDVNs = new address[](0);
        bytes memory ulnConfig = abi.encode(
            IEndpointContract.UlnConfig(
                confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
            )
        );

        IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](1);
        params[0] = IEndpointContract.SetConfigParam({dstEid: originEid, configType: 2, config: ulnConfig});

        vm.createSelectFork(destRpcUrl);
        vm.startBroadcast(deployerPrivateKey);
        bytes memory data =
            abi.encodeWithSelector(endpointContract.setConfig.selector, destOAppAddress, destReceiveLib, params);
        sig.execute(address(endpointContract), 0, data);
        // endpointContract.setConfig(destOAppAddress, destReceiveLib, params);
        vm.stopBroadcast();
    }

    function run() public {
        setOriginSendConfig();
        //setOriginReceiveConfig(); // Commenting these out applies minimal config
        //setDestSendConfig(); // Commenting these out applies minimal config
        // setDestReceiveConfig();
    }
}
