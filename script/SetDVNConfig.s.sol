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

    // string originRpcUrl = "https://rpc.taiko.xyz";
    // address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    // address originEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    // address originSendLib = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;
    // address originReceiveLib = 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    // address originExecutor = 0xa20DB4Ffe74A31D17fc24BD32a7DD7555441058e;
    // address originDVN = 0x88B27057A9e00c5F05DDa29241027afF63f9e6e0;
    // uint32 originEid = 30290;

    // string originRpcUrl = "https://phoenix-rpc.plumenetwork.xyz";
    // address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    // address originEndpoint = 0xC1b15d3B262bEeC0e3565C11C9e0F6134BdaCB36;
    // address originSendLib = 0xFe7C30860D01e28371D40434806F4A8fcDD3A098;
    // address originReceiveLib = 0x5B19bd330A84c049b62D5B0FC2bA120217a18C1C;
    // address originExecutor = 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d;
    // address originDVN = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b; // This should not be a Dead DVN
    // uint32 originEid = 30370;

    // string originRpcUrl = "https://rpc.soneium.org";
    // address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    // address originEndpoint = 0x4bCb6A963a9563C33569D7A512D35754221F3A19;
    // address originSendLib = 0x50351C9dA75CCC6d8Ea2464B26591Bb4bd616dD5;
    // address originReceiveLib = 0x364B548d8e6DB7CA84AaAFA54595919eCcF961eA;
    // address originExecutor = 0xAE3C661292bb4D0AEEe0588b4404778DF1799EE6;
    // address originDVN = 0xfDfA2330713A8e2EaC6e4f15918F11937fFA4dBE; // This should not be a Dead DVN
    // uint32 originEid = 30340;

    // string originRpcUrl = "https://rpc.morphl2.io";
    // address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    // address originEndpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    // address originSendLib = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    // address originReceiveLib = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
    // address originExecutor = 0xcCE466a522984415bC91338c232d98869193D46e;
    // address originDVN = 0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842; // This should not be a Dead DVN
    // uint32 originEid = 30322;

    string originRpcUrl = "https://rpc.ankr.com/kaia";
    address originOAppAddress = 0x00000000000E1A99dDDd5610111884278BDBda1D;
    address originEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address originSendLib = 0x9714Ccf1dedeF14BaB5013625DB92746C1358cb4;
    address originReceiveLib = 0x937AbA873827BF883CeD83CA557697427eAA46Ee;
    address originExecutor = 0xe149187a987F129FD3d397ED04a60b0b89D1669f;
    address originDVN = 0xc80233AD8251E668BecbC3B0415707fC7075501e; // This should not be a Dead DVN
    uint32 originEid = 30150;

    // string destRpcUrl = "https://eth.llamarpc.com";
    string destRpcUrl = "https://1rpc.io/eth";
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

    // function setOriginReceiveConfig() public {
    //     IEndpointContract endpointContract = IEndpointContract(originEndpoint);

    //     // ULN Configuration
    //     address[] memory requiredDVNs = new address[](2);
    //     requiredDVNs[0] = originDVN;
    //     address[] memory optionalDVNs = new address[](0);
    //     bytes memory ulnConfig = abi.encode(
    //         confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
    //     );

    //     IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](2);
    //     params[0] = IEndpointContract.SetConfigParam({dstEid: destEid, configType: 2, config: ulnConfig});

    //     vm.createSelectFork(originRpcUrl);
    //     vm.startBroadcast(deployerPrivateKey);
    //     endpointContract.setConfig(originOAppAddress, originReceiveLib, params);
    //     vm.stopBroadcast();
    // }

    // function setDestSendConfig() public {
    //     IEndpointContract endpointContract = IEndpointContract(destEndpoint);

    //     // ULN Configuration
    //     address[] memory requiredDVNs = new address[](2);
    //     requiredDVNs[0] = destDVN;
    //     address[] memory optionalDVNs = new address[](0);
    //     bytes memory ulnConfig = abi.encode(
    //         confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs
    //     );

    //     // Executor Configuration
    //     bytes memory executorConfig = abi.encode(maxMessageSize, destExecutor);

    //     IEndpointContract.SetConfigParam[] memory params = new IEndpointContract.SetConfigParam[](2);
    //     params[0] = IEndpointContract.SetConfigParam({dstEid: originEid, configType: 2, config: ulnConfig});
    //     params[1] = IEndpointContract.SetConfigParam({dstEid: originEid, configType: 1, config: executorConfig});

    //     vm.createSelectFork(destRpcUrl);
    //     vm.startBroadcast(deployerPrivateKey);
    //     endpointContract.setConfig(destOAppAddress, destSendLib, params);
    //     vm.stopBroadcast();
    // }

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
        setDestReceiveConfig();
    }
}
