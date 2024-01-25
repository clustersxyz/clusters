// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    OAppSenderUpgradeable, MessagingFee
} from "layerzero-oapp/contracts/oapp-upgradeable/OAppSenbderUpgradeable.sol";

contract InitiatorBeta is OAppSenderUpgradeable {
    uint32 public dstEid;

    function initialize(address endpoint_, address owner_, uint32 dstEid_, bytes32 peer_) public initializer {
        _initializeOAppCore(endpoint_, owner_);
        dstEid = dstEid_;
        setPeer(dstEid_, peer_);
    }

    function quote(bytes memory message, bytes memory options) public view returns (uint256 nativeFee) {
        MessagingFee memory msgQuote = _quote(dstEid, message, options, false);
        return msgQuote.nativeFee;
    }

    function lzSend(bytes memory message, bytes memory options) external payable {
        MessagingFee memory fee = MessagingFee({nativeFee: uint128(msg.value), lzTokenFee: 0});
        _lzSend(dstEid, message, options, fee, payable(msg.sender));
    }
}
