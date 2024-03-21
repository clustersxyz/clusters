// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {
    OAppSenderUpgradeable, MessagingFee
} from "layerzero-oapp/contracts/oapp-upgradeable/OAppSenderUpgradeable.sol";

contract InitiatorBeta is UUPSUpgradeable, OAppSenderUpgradeable {
    uint32 public dstEid;

    error Unauthorized();

    // Intended to prevent auto-verification of the contracts
    error StopVerification();
    function doNothing() public view {}

    /// UUPSUpgradeable Authentication ///

    function _authorizeUpgrade(address newImplementation) internal override {
        if (msg.sender != 0x000000dE1E80ea5a234FB5488fee2584251BC7e8) revert Unauthorized();
    }

    /// OAPPSender Functions ///

    function initialize(address endpoint_, address owner_) external initializer {
        _initializeOAppCore(endpoint_, owner_);
    }

    function setDstEid(uint32 dstEid_) external onlyOwner {
        dstEid = dstEid_;
    }

    function quote(bytes memory message, bytes memory options) external view returns (uint256 nativeFee) {
        MessagingFee memory msgQuote = _quote(dstEid, message, options, false);
        return msgQuote.nativeFee;
    }

    function lzSend(bytes memory calldata_, bytes memory options) external payable {
        MessagingFee memory fee = MessagingFee({nativeFee: uint128(msg.value), lzTokenFee: 0});
        bytes32 msgsender = bytes32(uint256(uint160(msg.sender)));
        _lzSend(dstEid, abi.encode(msgsender, calldata_), options, fee, payable(msg.sender));
    }
}
