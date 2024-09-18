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
        address pricingTemplate;
        address pricingProxy;
        address endpointTemplate;
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
    uint32 internal constant LZ_EID_HOLESKY = 40217;

    address internal constant LZ_END_SEPOLIA = 0x464570adA09869d8741132183721B4f0769a0287;
    address internal constant LZ_END_HOLESKY = 0x464570adA09869d8741132183721B4f0769a0287;

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
                deployments[forkId].pricingTemplate = address(pricing);
            } else {
                PricingFlat pricing = new PricingFlat();
                deployments[forkId].pricingTemplate = address(pricing);
            }
            vm.label(deployments[forkId].pricingTemplate, chain.concat(" Pricing Template"));
            deployments[forkId].pricingProxy = LibClone.deployERC1967(deployments[forkId].pricingTemplate);
            vm.label(deployments[forkId].pricingProxy, chain.concat(" Pricing Proxy"));
            if (isHarberger) {
                PricingHarberger(deployments[forkId].pricingProxy).initialize(deployer, block.timestamp);
            } else {
                PricingFlat(deployments[forkId].pricingProxy).initialize(deployer);
            }
        }
        // Deploy and initialize endpoint
        deployments[forkId].endpointTemplate = address(new Endpoint());
        vm.label(deployments[forkId].endpointTemplate, chain.concat(" Endpoint Template"));
        deployments[forkId].endpointProxy = LibClone.deployERC1967(deployments[forkId].endpointTemplate);
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
        deploy("Sepolia", vm.envString("SEPOLIA_RPC_URL"), true, true, LZ_EID_SEPOLIA, LZ_END_SEPOLIA);
        deploy("Holesky", vm.envString("HOLESKY_RPC_URL"), true, false, LZ_EID_HOLESKY, LZ_END_HOLESKY);
        configure();

        for (uint256 i; i < forkIds.length(); ++i) {
            Deployment memory deployment = deployments[forkIds.at(i)];
            if (deployment.pricingTemplate != address(0)) {
                console2.log(
                    deployment.chain.concat(" Pricing Template: ").concat(
                        deployment.pricingTemplate.toHexStringChecksummed()
                    )
                );
            }
            if (deployment.pricingProxy != address(0)) {
                console2.log(
                    deployment.chain.concat(" Pricing Proxy: ").concat(deployment.pricingProxy.toHexStringChecksummed())
                );
            }
            console2.log(
                deployment.chain.concat(" Endpoint Template: ").concat(
                    deployment.endpointTemplate.toHexStringChecksummed()
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
