// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {ClustersCommunityBaseBeta} from "clusters/beta/ClustersCommunityBaseBeta.sol";
import {OptionsBuilder} from "layerzero-oapp/contracts/oapp/libs/OptionsBuilder.sol";
import {
    OAppSenderUpgradeable, MessagingFee
} from "layerzero-oapp/contracts/oapp-upgradeable/OAppSenderUpgradeable.sol";

/// @title ClustersCommunityHubBeta
/// @notice The initiator contract for clusters community sales.
contract ClustersCommunityInitiatorBeta is OAppSenderUpgradeable, ReentrancyGuard, ClustersCommunityBaseBeta {
    using OptionsBuilder for bytes;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The storage struct for the contract.
    struct ClustersCommunityInitiatorBetaStorage {
        uint32 dstEid;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersCommunityInitiatorBetaStorage()
        internal
        pure
        returns (ClustersCommunityInitiatorBetaStorage storage $)
    {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersCommunityInitiatorBetaStorage")))`.
            $.slot := 0xc3d7966f8edf259843 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when the destination endpoint ID is set.
    event DstEidSet(uint32 eid);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Insufficient native payment.
    error InsufficientNativePayment();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the contract.
    function initialize(address endpoint_, address owner_) public initializer onlyProxy {
        _initializeOAppCore(endpoint_, owner_);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC WRITE FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Places a bid.
    ///      If any token is `address(0)`, it is treated as the native token.
    ///      All tokens will not be bridged.
    function placeBid(BidConfig calldata bidConfig, uint256 gas) public payable nonReentrant {
        uint256 requiredNativeValue;
        address vault = createVault(bidConfig.paymentRecipient);
        if (bidConfig.token == address(0)) {
            requiredNativeValue = bidConfig.amount;
            SafeTransferLib.safeTransferETH(vault, bidConfig.amount);
        } else {
            SafeTransferLib.safeTransferFrom(bidConfig.token, msg.sender, vault, bidConfig.amount);
        }
        _sendBids(_encodeBidMessage(bidConfig), requiredNativeValue, gas);
    }

    /// @dev Places multiple bids.
    ///      If any token is `address(0)`, it is treated as the native token.
    ///      All tokens will not be bridged.
    function placeBids(BidConfig[] calldata bidConfigs, uint256 gas) public payable nonReentrant {
        uint256 requiredNativeValue;
        for (uint256 i; i < bidConfigs.length; ++i) {
            BidConfig calldata bidConfig = bidConfigs[i];
            address vault = createVault(bidConfig.paymentRecipient);
            if (bidConfig.token == address(0)) {
                requiredNativeValue += bidConfig.amount;
                SafeTransferLib.safeTransferETH(vault, bidConfig.amount);
            } else {
                SafeTransferLib.safeTransferFrom(bidConfig.token, msg.sender, address(this), bidConfig.amount);
            }
        }
        _sendBids(_encodeBidsMessage(bidConfigs), requiredNativeValue, gas);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the Layerzero destination endpoint ID.
    function dstEid() public view returns (uint32) {
        return _getClustersCommunityInitiatorBetaStorage().dstEid;
    }

    /// @dev Returns the amount of native gas fee required to place a bid.
    function quoteForBid(BidConfig calldata bidConfig, uint256 gas) public view returns (uint256) {
        return _quoteNativeFee(_encodeBidMessage(bidConfig), gas);
    }

    /// @dev Returns the amount of native gas fee required to place the bids.
    function quoteForBids(BidConfig[] calldata bidConfigs, uint256 gas) public view returns (uint256) {
        return _quoteNativeFee(_encodeBidsMessage(bidConfigs), gas);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Enables the owner to set the destination endpoint ID.
    function setDstEid(uint32 eid) public onlyOwnerOrRoles(abi.encode(ADMIN_ROLE)) {
        _getClustersCommunityInitiatorBetaStorage().dstEid = eid;
        emit DstEidSet(eid);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Used by `placeBid` and `placeBids`.
    function _sendBids(bytes memory encoded, uint256 requiredNativeValue, uint256 gas) internal {
        uint256 nativeFee = _quoteNativeFee(encoded, gas);
        uint256 requiredNativeTotal = nativeFee + requiredNativeValue;
        if (msg.value < requiredNativeTotal) revert InsufficientNativePayment();
        _lzSend(dstEid(), encoded, _defaultOptions(gas), MessagingFee(nativeFee, 0), payable(msg.sender));
        if (msg.value > requiredNativeTotal) {
            SafeTransferLib.forceSafeTransferETH(msg.sender, msg.value - requiredNativeTotal);
        }
    }

    /// @dev Override to remove the `if (msg.value != nativeFee) revert()`.
    function _payNative(uint256 nativeFee) internal virtual override returns (uint256) {
        return nativeFee;
    }

    /// @dev Returns the default options that encodes `gas`.
    function _defaultOptions(uint256 gas) internal pure returns (bytes memory) {
        if (gas >= 1 << 128) revert();
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(gas), 0);
    }

    /// @dev Returns the required native fee for Layerzero.
    function _quoteNativeFee(bytes memory encoded, uint256 gas) internal view returns (uint256) {
        return _quote(dstEid(), encoded, _defaultOptions(gas), false).nativeFee;
    }

    /// @dev Encodes the bid calldata.
    function _encodeBidMessage(BidConfig calldata bidConfig) internal view returns (bytes memory) {
        return abi.encode(
            block.chainid,
            msg.sender,
            abi.encodeWithSignature("placeBid((address,uint256,address,bytes32,bytes32,bytes32))", bidConfig)
        );
    }

    /// @dev Encodes the bids calldata.
    function _encodeBidsMessage(BidConfig[] calldata bidConfigs) internal view returns (bytes memory) {
        return abi.encode(
            block.chainid,
            msg.sender,
            abi.encodeWithSignature("placeBids((address,uint256,address,bytes32,bytes32,bytes32)[])", bidConfigs)
        );
    }
}
