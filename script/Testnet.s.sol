// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {IOAppCore} from "layerzero-oapp/contracts/oapp/interfaces/IOAppCore.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

contract ClustersScript is Script {
    address internal constant ADMIN = address(uint160(uint256(keccak256(abi.encodePacked("ADMIN")))));
    address internal constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant LZ_END_GOERLI = 0x464570adA09869d8741132183721B4f0769a0287;
    address internal constant LZ_END_SEPOLIA = 0x464570adA09869d8741132183721B4f0769a0287;
    uint32 internal constant LZ_EID_GOERLI = 40121;
    uint32 internal constant LZ_EID_SEPOLIA = 40161;

    string internal GOERLI_RPC_URL = vm.envString("GOERLI_RPC_URL");
    string internal SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    uint256 internal goerliFork;
    uint256 internal sepoliaFork;

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {
        goerliFork = vm.createFork(GOERLI_RPC_URL);
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        bytes memory endpointInit;

        vm.selectFork(goerliFork);
        vm.startBroadcast(deployerPrivateKey);
        PricingHarberger goerliPricing = new PricingHarberger(block.timestamp);
        Endpoint goerliEndpoint = new Endpoint();
        endpointInit = abi.encodeWithSignature(
            "initialize(address,address,address,address)", deployer, ADMIN, SIGNER, LZ_END_GOERLI
        );
        IEndpoint goerliProxy =
            IEndpoint(address(new TransparentUpgradeableProxy(address(goerliEndpoint), ADMIN, endpointInit)));
        ClustersHub goerliClusters =
            new ClustersHub(address(goerliPricing), address(goerliProxy), block.timestamp + 5 minutes);
        goerliProxy.setClustersAddr(address(goerliClusters));
        vm.stopBroadcast();

        vm.selectFork(sepoliaFork);
        vm.startBroadcast(deployerPrivateKey);
        //PricingHarberger sepoliaPricing = new PricingHarberger(block.timestamp);
        Endpoint sepoliaEndpoint = new Endpoint();
        endpointInit = abi.encodeWithSignature(
            "initialize(address,address,address,address)", deployer, ADMIN, SIGNER, LZ_END_SEPOLIA
        );
        IEndpoint sepoliaProxy =
            IEndpoint(address(new TransparentUpgradeableProxy(address(sepoliaEndpoint), ADMIN, endpointInit)));

        //ClustersHub sepoliaClusters = new ClustersHub(address(sepoliaPricing), address(sepoliaProxy),
        // block.timestamp);
        //sepoliaProxy.setClustersAddr(address(sepoliaClusters));
        IOAppCore(address(sepoliaProxy)).setPeer(LZ_EID_GOERLI, addressToBytes32(address(goerliProxy)));
        sepoliaProxy.setDstEid(LZ_EID_GOERLI);
        vm.stopBroadcast();

        vm.selectFork(goerliFork);
        vm.startBroadcast(deployerPrivateKey);
        IOAppCore(address(goerliProxy)).setPeer(LZ_EID_SEPOLIA, addressToBytes32(address(sepoliaProxy)));
        vm.stopBroadcast();
    }
}
