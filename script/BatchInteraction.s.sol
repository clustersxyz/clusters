// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";

import {Endpoint} from "../src/Endpoint.sol";
import {ClustersHubBeta} from "../src/beta/ClustersHubBeta.sol";

interface GasliteDrop {
    function airdropETH(address[] calldata _addresses, uint256[] calldata _amounts) external payable;
}

contract BatchInteractionScript is Script {
    using OptionsBuilder for bytes;

    uint256 internal sepoliaFork;
    Endpoint internal endpoint;
    ClustersHubBeta internal proxy;
    GasliteDrop internal drop;

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function setUp() public {
        uint256 mainnetFork = vm.createFork("https://eth.llamarpc.com");
        vm.selectFork(mainnetFork);
        proxy = ClustersHubBeta(0x00000000000E1A99dDDd5610111884278BDBda1D);
        drop = GasliteDrop(0x09350F89e2D7B6e96bA730783c2d76137B045FEF);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console2.log(deployer);
        require(deployer == 0x443eDFF556D8fa8BfD69c3943D6eaf34B6a048e0, "wrong addy");

        /// BATCH BIDDING ///

        // uint256 SIZE = 2;
        // uint256[] memory amounts = new uint256[](SIZE);
        // bytes32[] memory names = new bytes32[](SIZE);
        // for (uint256 i = 0; i < SIZE; i++) {
        //     amounts[i] = 0.01 ether;
        // }

        // names[0] = "name0";
        // names[1] = "name1";

        // bytes memory data =
        //     abi.encodeWithSelector(proxy.placeBids.selector, amounts, names);

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250_000, uint128(0.02 ether));

        // uint256 totalValue = SIZE * 0.01 ether;
        // totalValue = 0.20 ether;
        // proxy.placeBids{value: totalValue}(amounts, names);

        // (uint256 nativeFee,) = endpoint.quote(40121, data, options, false);
        // endpoint.lzSend{value: nativeFee}(data, options, payable(msg.sender));

        /// BATCH REFUNDING ///

        uint256 SIZE = 2;
        address[] memory refundAddresses = new address[](SIZE);
        uint256[] memory refundAmounts = new uint256[](SIZE);

        // refundAddresses[0] = address(0x0000000000000000000000004592960cf42342085c7d15afb52fcfe4c698a9b9);
        // refundAmounts[0] = 10000000000000000;
        // refundAddresses[1] = address(0x0000000000000000000000002ef893e5c362ac25bef41c5a7ef2e046475c8678);
        // refundAmounts[1] = 10000000000000000;
        // refundAddresses[2] = address(0x0000000000000000000000001421153b3c62ae5ae038a76c940a28b0fce427e3);
        // refundAmounts[2] = 10000000000000000;
        // refundAddresses[3] = address(0x0000000000000000000000004dde2aadbde7031ce4ca2aa45ae0cabc0f90d242);
        // refundAmounts[3] = 10000000000000000;

        refundAddresses[0] = address(0x000000000000000000000000e6899b76a2f01de328954245947b2568a68e0f9f);
        refundAmounts[0] = 10000000000000000;
        refundAddresses[1] = address(0x0000000000000000000000006e105228c8c0510e5c68e04b3b92f047af56189e);
        refundAmounts[1] = 10000000000000000;

        uint256 totalRefund = 0;
        for (uint256 i = 0; i < SIZE; i++) {
            totalRefund += refundAmounts[i];
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 prodTotalRefund = 0.02 ether;
        require(prodTotalRefund == totalRefund, "bad total");
        drop.airdropETH{value: totalRefund}(refundAddresses, refundAmounts);

        vm.stopBroadcast();
    }
}
