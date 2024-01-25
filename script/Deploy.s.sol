// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibString} from "solady/utils/LibString.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {PricingFlat} from "../src/PricingFlat.sol";
import {PricingHarberger} from "../src/PricingHarberger.sol";
import {Endpoint} from "../src/Endpoint.sol";
import {ClustersHub} from "../src/ClustersHub.sol";
import {IPricing} from "../src/interfaces/IPricing.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {IOAppCore} from "layerzero-oapp/contracts/oapp/interfaces/IOAppCore.sol";

contract DeployScript is Script {
    using LibString for string;
    using LibString for uint256;
    using LibString for address;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Deployment {
        string chain;
        address pricingImplementation;
        address pricingProxy;
        address endpointImplementation;
        address endpointProxy;
        address clusters;
        address layerzero;
        uint32 dstEid;
    }

    uint256 internal deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);
    address internal constant signer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    EnumerableSet.UintSet internal forkIds;
    mapping(uint256 forkId => Deployment) internal deployments;

    uint32 internal constant LZ_EID_SEPOLIA = 40161;
    uint32 internal constant LZ_EID_ARBITRUM_SEPOLIA = 40231;
    uint32 internal constant LZ_EID_OPTIMISM_SEPOLIA = 40232;
    uint32 internal constant LZ_EID_SCROLL_SEPOLIA = 40170;
    uint32 internal constant LZ_EID_FRAME_SEPOLIA = 40222;
    uint32 internal constant LZ_EID_HOLESKY = 40217;
    uint32 internal constant LZ_EID_GOERLI = 40121;
    uint32 internal constant LZ_EID_ARBITRUM_GOERLI = 40143;
    uint32 internal constant LZ_EID_POLYGON_GOERLI = 40158;
    uint32 internal constant LZ_EID_MANTLE_GOERLI = 40181;
    uint32 internal constant LZ_EID_ZKSYNC_GOERLI = 40165;

    // All chains above use the same address so far
    address internal constant LZ_END_SHARED = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant LZ_END_ZKSYNC = 0x0DA8aA8452eCC2f6241Ee41ed535efB64BEc40ea;

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {}

    function deploy(
        string memory chain,
        string memory rpcUrl,
        bool isHarberger,
        bool isHub,
        uint32 dstEid,
        address lzEndpoint
    ) internal {
        // Prep fork
        uint256 forkId = vm.createFork(rpcUrl);
        forkIds.add(forkId);
        vm.selectFork(forkId);
        vm.startBroadcast(deployerPrivateKey);
        // Deploy and initialize pricing
        if (isHub) {
            if (isHarberger) {
                PricingHarberger pricing = new PricingHarberger();
                deployments[forkId].pricingImplementation = address(pricing);
            } else {
                PricingFlat pricing = new PricingFlat();
                deployments[forkId].pricingImplementation = address(pricing);
            }
            vm.label(deployments[forkId].pricingImplementation, chain.concat(" Pricing Implementation"));
            deployments[forkId].pricingProxy = LibClone.deployERC1967(deployments[forkId].pricingImplementation);
            vm.label(deployments[forkId].pricingProxy, chain.concat(" Pricing Proxy"));
            if (isHarberger) {
                PricingHarberger(deployments[forkId].pricingProxy).initialize(deployer, block.timestamp);
            } else {
                PricingFlat(deployments[forkId].pricingProxy).initialize(deployer);
            }
        }
        // Deploy and initialize endpoint
        deployments[forkId].endpointImplementation = address(new Endpoint());
        vm.label(deployments[forkId].endpointImplementation, chain.concat(" Endpoint Implementation"));
        deployments[forkId].endpointProxy = LibClone.deployERC1967(deployments[forkId].endpointImplementation);
        vm.label(deployments[forkId].endpointProxy, chain.concat(" Endpoint Proxy"));
        Endpoint(deployments[forkId].endpointProxy).initialize(deployer, signer, lzEndpoint);
        if (isHub) {
            deployments[forkId].clusters = address(
                new ClustersHub(
                    deployments[forkId].pricingProxy, deployments[forkId].endpointProxy, block.timestamp + 5 minutes
                )
            );
            vm.label(deployments[forkId].clusters, chain.concat(" Clusters Hub"));
            IEndpoint(deployments[forkId].endpointProxy).setClustersAddr(deployments[forkId].clusters);
        } else {
            // Deploy Spoke infrastructure here
        }
        // Store remaining deployment information
        deployments[forkId].chain = chain;
        deployments[forkId].layerzero = lzEndpoint;
        deployments[forkId].dstEid = dstEid;
        vm.stopBroadcast();
    }

    function configure() internal {
        uint256[] memory forks = forkIds.values();
        for (uint256 i; i < forks.length; ++i) {
            address endpointProxy = deployments[i].endpointProxy;
            vm.selectFork(forks[i]);
            vm.startBroadcast(deployerPrivateKey);
            for (uint256 j; j < forks.length; ++j) {
                if (i == j) continue;
                IOAppCore(endpointProxy).setPeer(
                    deployments[forks[j]].dstEid, _addressToBytes32(deployments[forks[j]].endpointProxy)
                );
            }
            if (i == 0) {
                // Set dstEid on hub to enable replication
            } else {
                IEndpoint(endpointProxy).setDstEid(deployments[forks[0]].dstEid);
            }
            vm.stopBroadcast();
        }
    }

    function run() public {
        deploy("Sepolia", vm.envString("SEPOLIA_RPC_URL"), true, true, LZ_EID_SEPOLIA, LZ_END_SHARED);
        deploy("Arbitrum Sepolia", vm.envString("ARBITRUM_SEPOLIA_RPC_URL"), true, false, LZ_EID_ARBITRUM_SEPOLIA, LZ_END_SHARED);
        deploy("Optimism Sepolia", vm.envString("OPTIMISM_SEPOLIA_RPC_URL"), true, false, LZ_EID_OPTIMISM_SEPOLIA, LZ_END_SHARED);
        deploy("Holesky", vm.envString("HOLESKY_RPC_URL"), true, false, LZ_EID_HOLESKY, LZ_END_SHARED);
        deploy("Polygon zkEVM Goerli", vm.envString("POLYGON_GOERLI_RPC_URL"), true, false, LZ_EID_POLYGON_GOERLI, LZ_END_SHARED);
        //deploy("Scroll Sepolia", vm.envString("SCROLL_SEPOLIA_RPC_URL"), true, false, LZ_EID_SCROLL_SEPOLIA, LZ_END_SHARED);
        ///deploy("Frame Sepolia", vm.envString("FRAME_SEPOLIA_RPC_URL"), true, false, LZ_EID_FRAME_SEPOLIA, LZ_END_SHARED);
        ///deploy("Mantle Goerli", vm.envString("MANTLE_GOERLI_RPC_URL"), true, false, LZ_EID_MANTLE_GOERLI, LZ_END_SHARED);
        ///deploy("zkSync Goerli", vm.envString("ZKSYNC_GOERLI_RPC_URL"), true, false, LZ_EID_ZKSYNC_GOERLI, LZ_END_ZKSYNC);
        configure();

        for (uint256 i; i < forkIds.length(); ++i) {
            Deployment memory deployment = deployments[forkIds.at(i)];
            if (deployment.pricingImplementation != address(0)) {
                console2.log(
                    deployment.chain.concat(" Pricing Implementation: ").concat(
                        deployment.pricingImplementation.toHexStringChecksummed()
                    )
                );
            }
            if (deployment.pricingProxy != address(0)) {
                console2.log(
                    deployment.chain.concat(" Pricing Proxy: ").concat(deployment.pricingProxy.toHexStringChecksummed())
                );
            }
            console2.log(
                deployment.chain.concat(" Endpoint Implementation: ").concat(
                    deployment.endpointImplementation.toHexStringChecksummed()
                )
            );
            console2.log(
                deployment.chain.concat(" Endpoint Proxy: ").concat(deployment.endpointProxy.toHexStringChecksummed())
            );
            if (deployment.clusters != address(0)) {
                console2.log(
                    deployment.chain.concat(" Clusters: ").concat(deployment.clusters.toHexStringChecksummed())
                );
            }
            console2.log(
                deployment.chain.concat(" LayerZero Endpoint: ").concat(deployment.layerzero.toHexStringChecksummed())
            );
            console2.log(deployment.chain.concat(" LayerZero DstEid: ").concat(uint256(deployment.dstEid).toString()));
            console2.log("");
        }
    }
}
