// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

import {Endpoint} from "../src/Endpoint.sol";

contract RemoteBuyNameScript is Script {
    using OptionsBuilder for bytes;

    address internal constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant SEPOLIA_ENDPOINT = 0x077D04dd19Ba7bF13314059e5F4EF90FE0F848B3;

    string internal SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    uint256 internal sepoliaFork;
    Endpoint internal endpoint;

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaFork);
        endpoint = Endpoint(SEPOLIA_ENDPOINT);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        bytes memory data =
            abi.encodeWithSignature("buyName(bytes32,uint256,string)", addressToBytes32(deployer), 0.02 ether, "zodomo");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000 gwei, uint128(0.02 ether));

        vm.startBroadcast(deployerPrivateKey);
        (uint256 nativeFee,) = endpoint.quote(40121, data, options, false);
        endpoint.lzSend{value: nativeFee}(data, options, nativeFee, payable(msg.sender));
        vm.stopBroadcast();
    }
}
