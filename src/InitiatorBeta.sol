// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Origin, OAppReceiverUpgradeable} from "layerzero-oapp/contracts/oapp-upgradeable/OAppReceiverUpgradeable.sol";
import {
    OAppSenderUpgradeable, MessagingFee
} from "layerzero-oapp/contracts/oapp-upgradeable/OAppSenderUpgradeable.sol";

contract InitiatorBeta is UUPSUpgradeable, OAppSenderUpgradeable {
    uint32 public dstEid;

    error Unauthorized();

    /// UUPSUpgradeable Management ///

    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
    }

    /// OAPPSender Functions ///

    function initialize(address endpoint_, address owner_) public initializer {
        _initializeOAppCore(endpoint_, owner_);
    }

    function setDstEid(uint32 dstEid_) public onlyOwner {
        dstEid = dstEid_;
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
