// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {IPricing} from "../src/interfaces/IPricing.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {IOAppCore} from "layerzero-oapp/contracts/oapp/interfaces/IOAppCore.sol";
import {ClustersHub} from "../src/ClustersHub.sol";

contract TestnetScript is Script {
    address internal constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant LZ_END_GOERLI = 0x464570adA09869d8741132183721B4f0769a0287;
    address internal constant LZ_END_SEPOLIA = 0x464570adA09869d8741132183721B4f0769a0287;
    address internal constant LZ_END_HOLESKY = 0x464570adA09869d8741132183721B4f0769a0287;
    uint32 internal constant LZ_EID_GOERLI = 40121;
    uint32 internal constant LZ_EID_SEPOLIA = 40161;
    uint32 internal constant LZ_EID_HOLESKY = 40217;

    string internal SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string internal GOERLI_RPC_URL = vm.envString("GOERLI_RPC_URL");
    string internal HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");
    uint256 internal sepoliaFork;
    uint256 internal goerliFork;
    uint256 internal holeskyFork;

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        goerliFork = vm.createFork(GOERLI_RPC_URL);
        holeskyFork = vm.createFork(HOLESKY_RPC_URL);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Sepolia Hub Deployment
        vm.selectFork(sepoliaFork);
        vm.startBroadcast(deployerPrivateKey);
        PricingHarberger sepoliaPricing = new PricingHarberger();
        vm.label(address(sepoliaPricing), "Sepolia Pricing Template");
        IPricing sepoliaPricingProxy = IPricing(LibClone.deployERC1967(address(sepoliaPricing)));
        vm.label(address(sepoliaPricingProxy), "Sepolia Pricing Proxy");
        PricingHarberger(address(sepoliaPricingProxy)).initialize(msg.sender, block.timestamp + 1 minutes);
        Endpoint sepoliaEndpoint = new Endpoint();
        vm.label(address(sepoliaEndpoint), "Sepolia Endpoint Template");
        IEndpoint sepoliaEndpointProxy = IEndpoint(LibClone.deployERC1967(address(sepoliaEndpoint)));
        vm.label(address(sepoliaEndpointProxy), "Sepolia Endpoint Proxy");
        Endpoint(address(sepoliaEndpointProxy)).initialize(deployer, SIGNER, LZ_END_SEPOLIA);
        ClustersHub sepoliaClusters =
            new ClustersHub(address(sepoliaPricingProxy), address(sepoliaEndpointProxy), block.timestamp + 5 minutes);
        vm.label(address(sepoliaClusters), "Sepolia Clusters Hub");
        sepoliaEndpointProxy.setClustersAddr(address(sepoliaClusters));
        vm.stopBroadcast();

        // Goerli Spoke Deployment
        vm.selectFork(goerliFork);
        vm.startBroadcast(deployerPrivateKey);
        //PricingHarberger goerliPricing = new PricingHarberger(block.timestamp);
        //vm.label(address(goerliPricing), "Goerli Pricing Template");
        //IPricing goerliPricingProxy = IPricing(LibClone.deployERC1967(address(goerliPricing)));
        //vm.label(address(goerliPricingProxy), "Goerli Pricing Proxy");
        //PricingHarberger(address(goerliPricingProxy)).initialize(msg.sender, block.timestamp + 1 minutes);
        Endpoint goerliEndpoint = new Endpoint();
        vm.label(address(goerliEndpoint), "Goerli Endpoint Template");
        IEndpoint goerliEndpointProxy = IEndpoint(LibClone.deployERC1967(address(goerliEndpoint)));
        vm.label(address(goerliEndpointProxy), "Goerli Endpoint Proxy");
        Endpoint(address(goerliEndpointProxy)).initialize(deployer, SIGNER, LZ_END_GOERLI);
        //ClustersHub goerliClusters = new ClustersHub(address(goerliPricingProxy), address(goerliEndpointProxy),
        // block.timestamp);
        //vm.label(address(goerliClusters), "Goerli Clusters Spoke");
        //goerliEndpointProxy.setClustersAddr(address(goerliClusters));
        IOAppCore(address(goerliEndpointProxy)).setPeer(LZ_EID_SEPOLIA, addressToBytes32(address(sepoliaEndpointProxy)));
        goerliEndpointProxy.setDstEid(LZ_EID_SEPOLIA);
        vm.stopBroadcast();

        // Holesky Spoke Deployment
        vm.selectFork(holeskyFork);
        vm.startBroadcast(deployerPrivateKey);
        //PricingHarberger holeskyPricing = new PricingHarberger(block.timestamp);
        //vm.label(address(holeskyPricing), "Holesky Pricing Template");
        //IPricing holeskyPricingProxy = IPricing(LibClone.deployERC1967(address(holeskyPricing)));
        //vm.label(address(holeskyPricingProxy), "Holesky Pricing Proxy");
        //PricingHarberger(address(holeskyPricingProxy)).initialize(msg.sender, block.timestamp + 1 minutes);
        Endpoint holeskyEndpoint = new Endpoint();
        vm.label(address(holeskyEndpoint), "Holesky Endpoint Template");
        IEndpoint holeskyEndpointProxy = IEndpoint(LibClone.deployERC1967(address(holeskyEndpoint)));
        vm.label(address(holeskyEndpointProxy), "Holesky Endpoint Proxy");
        Endpoint(address(holeskyEndpointProxy)).initialize(deployer, SIGNER, LZ_END_HOLESKY);
        //ClustersHub holeskyClusters = new ClustersHub(address(holeskyPricingProxy), address(holeskyEndpointProxy),
        // block.timestamp);
        //vm.label(address(holeskyClusters), "Holesky Clusters Spoke");
        //holeskyEndpointProxy.setClustersAddr(address(holeskyClusters));
        IOAppCore(address(holeskyEndpointProxy)).setPeer(
            LZ_EID_SEPOLIA, addressToBytes32(address(sepoliaEndpointProxy))
        );
        IOAppCore(address(holeskyEndpointProxy)).setPeer(LZ_EID_GOERLI, addressToBytes32(address(goerliEndpointProxy)));
        holeskyEndpointProxy.setDstEid(LZ_EID_SEPOLIA);
        vm.stopBroadcast();

        // Post-deployment Goerli config finalization
        vm.selectFork(goerliFork);
        vm.startBroadcast(deployerPrivateKey);
        IOAppCore(address(goerliEndpointProxy)).setPeer(LZ_EID_HOLESKY, addressToBytes32(address(holeskyEndpointProxy)));
        vm.stopBroadcast();

        // Post-deployment Sepolia config finalization
        vm.selectFork(sepoliaFork);
        vm.startBroadcast(deployerPrivateKey);
        IOAppCore(address(sepoliaEndpointProxy)).setPeer(LZ_EID_GOERLI, addressToBytes32(address(goerliEndpointProxy)));
        IOAppCore(address(sepoliaEndpointProxy)).setPeer(
            LZ_EID_HOLESKY, addressToBytes32(address(holeskyEndpointProxy))
        );
        // No DstEid is set on Sepolia Hub as that engages replication, which is not yet fully implemented
        vm.stopBroadcast();

        // Check state
        vm.selectFork(sepoliaFork);
        console2.log("Sepolia Pricing:");
        console2.log(address(sepoliaPricingProxy));
        console2.log("Sepolia Endpoint:");
        console2.log(address(sepoliaEndpointProxy));
        console2.log("Sepolia Clusters Hub:");
        console2.log(address(sepoliaClusters));
        //console2.log(sepoliaEndpointProxy.dstEid());
        //console2.log(Ownable(address(sepoliaEndpointProxy)).owner());
        //console2.logBytes32(IOAppCore(address(sepoliaEndpointProxy)).peers(LZ_EID_GOERLI));
        //console2.logBytes32(IOAppCore(address(sepoliaEndpointProxy)).peers(LZ_EID_HOLESKY));
        vm.selectFork(goerliFork);
        console2.log("Goerli Endpoint:");
        console2.log(address(goerliEndpointProxy));
        //console2.log(goerliEndpointProxy.dstEid());
        //console2.log(Ownable(address(goerliEndpointProxy)).owner());
        //console2.logBytes32(IOAppCore(address(goerliEndpointProxy)).peers(LZ_EID_SEPOLIA));
        //console2.logBytes32(IOAppCore(address(goerliEndpointProxy)).peers(LZ_EID_HOLESKY));
        vm.selectFork(holeskyFork);
        console2.log("Holesky Endpoint:");
        console2.log(address(holeskyEndpointProxy));
        //console2.log(holeskyEndpointProxy.dstEid());
        //console2.log(Ownable(address(holeskyEndpointProxy)).owner());
        //console2.logBytes32(IOAppCore(address(holeskyEndpointProxy)).peers(LZ_EID_SEPOLIA));
        //console2.logBytes32(IOAppCore(address(holeskyEndpointProxy)).peers(LZ_EID_GOERLI));
    }
}
