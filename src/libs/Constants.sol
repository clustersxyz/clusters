// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract Constants {
    bytes4 internal constant MULTICALL_SELECTOR = bytes4(keccak256("multicall(bytes[])"));
    bytes4 internal constant ADD_SELECTOR = bytes4(keccak256("add(bytes32,bytes32)"));
    bytes4 internal constant VERIFY_SELECTOR = bytes4(keccak256("verify(bytes32,uint256)"));
    bytes4 internal constant REMOVE_SELECTOR = bytes4(keccak256("remove(bytes32,bytes32)"));
    bytes4 internal constant BUY_NAME_SELECTOR = bytes4(keccak256("buyName(bytes32,uint256,string)"));
    bytes4 internal constant FUND_NAME_SELECTOR = bytes4(keccak256("fundName(bytes32,uint256,string)"));
    bytes4 internal constant TRANSFER_NAME_SELECTOR = bytes4(keccak256("transferName(bytes32,string,uint256)"));
    bytes4 internal constant POKE_NAME_SELECTOR = bytes4(keccak256("pokeName(string)"));
    bytes4 internal constant BID_NAME_SELECTOR = bytes4(keccak256("bidName(bytes32,uint256,string)"));
    bytes4 internal constant REDUCE_BID_SELECTOR = bytes4(keccak256("reduceBid(bytes32,string,uint256)"));
    bytes4 internal constant ACCEPT_BID_SELECTOR = bytes4(keccak256("acceptBid(bytes32,string)"));
    bytes4 internal constant REFUND_BID_SELECTOR = bytes4(keccak256("refundBid(bytes32)"));
    bytes4 internal constant SET_DEFAULT_CLUSTER_NAME_SELECTOR =
        bytes4(keccak256("setDefaultClusterName(bytes32,string)"));
    bytes4 internal constant SET_WALLET_NAME_SELECTOR = bytes4(keccak256("setWalletName(bytes32,bytes32,string)"));
    bytes4 internal constant GAS_AIRDROP_SELECTOR = bytes4(keccak256("gasAirdrop(bytes32,uint256)"));
}
