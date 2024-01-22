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
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
import "../lib/LayerZero-v2/protocol/contracts/EndpointV2.sol";

contract TestpadScript is Script {
    using OptionsBuilder for bytes;

    address internal constant HOLESKY_ENDPOINT = 0xc986CB24E8422a179D0799511D42275BcB148714;

    string internal HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");
    uint256 internal holeskyFork;

    /// @dev Convert address to bytes32
    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {
        holeskyFork = vm.createFork(HOLESKY_RPC_URL);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        IEndpoint endpoint = IEndpoint(HOLESKY_ENDPOINT);
        IOAppCore lzEndpoint = IOAppCore(HOLESKY_ENDPOINT);

        vm.selectFork(holeskyFork);
        bytes memory data = abi.encodeWithSignature(
            "buyName(bytes32,uint256,string)", _addressToBytes32(deployer), 0.01 ether, "zodomo"
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(300_000 gwei, uint128(0.01 ether));
        (uint256 nativeFee,) = endpoint.quote(40161, data, options, false);
        bytes memory results = endpoint.lzSend{value: nativeFee}(data, options, deployer);

        console2.log(nativeFee);
        console2.log(endpoint.dstEid());
        console2.log(deployer);
        console2.log(Ownable(HOLESKY_ENDPOINT).owner());
        console2.logBytes32(lzEndpoint.peers(40161));
        console2.logBytes(results);
    }
}
