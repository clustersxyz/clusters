// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {FixedPointMathLib as F} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {LibBit} from "solady/utils/LibBit.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MessageHubLibV1 as MessageHubLib} from "clusters/MessageHubLibV1.sol";

/// @title ClustersMarketV1
/// @notice All prices are in Ether.
contract ClustersMarketV1 is UUPSUpgradeable, Initializable, Ownable, ReentrancyGuardTransient {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev A struct to return the information of a name.
    struct NameInfo {
        // The id of the name.
        uint256 id;
        // The current owner of the name.
        address owner;
        // The timestamp of the start of current ownership.
        uint256 startTimestamp;
        // Whether the name is registered.
        bool isRegistered;
        // Price integral last price.
        uint256 lastPrice;
        // Price integral last update timestamp.
        uint256 lastUpdated;
        // Bid amount.
        uint256 bidAmount;
        // Bid last update timestamp.
        uint256 bidUpdated;
        // Bidder on the name.
        address bidder;
        // Amount backing the name.
        uint256 backing;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The storage struct for a bid.
    struct Bid {
        // Price integral last price.
        uint88 lastPrice;
        // Price integral last update timestamp.
        uint40 lastUpdated;
        // Amount backing the name.
        uint88 backing;
        // Bid last update timestamp.
        uint40 bidUpdated;
        // Bidder on the name.
        address bidder;
        // Bid amount.
        uint88 bidAmount;
    }

    /// @dev The storage struct for the contract.
    struct ClustersMarketStorage {
        // The stateless pricing contract and NFT contract. Packed.
        // They both have at least 4 leading zero bytes. Let's save a SLOAD.
        // Bits Layout:
        // - [0..127]   `pricing`.
        // - [128..255] `nft`.
        uint256 contracts;
        // Mapping of `clusterName` to `bid`.
        mapping(bytes32 => Bid) bids;
        // The total amount that is locked in bids. To prevent over withdrawing.
        uint88 totalBidBacking;
        // The minimum bid increment (in Ether wei).
        uint88 minBidIncrement;
        // The number of seconds that must pass since the last bid update for the bid to be reduced.
        uint32 bidTimelock;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersMarketStorage() internal pure returns (ClustersMarketStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersMarketStorage")))`.
            $.slot := 0xda8b89020ecb842518 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The pricing contract has been set.
    event PricingContractSet(address newContract);

    /// @dev The NFT contract has been set.
    event NFTContractSet(address newContract);

    /// @dev The name has been purchased.
    event Bought(bytes32 indexed clusterName, address indexed by, uint256 price);

    /// @dev The backing for `clusterName` has been increased.
    event Funded(bytes32 indexed clusterName, address indexed by, uint256 oldBacking, uint256 newBacking);

    /// @dev The `clusterName` has been poked.
    event Poked(bytes32 indexed clusterName, address indexed by);

    /// @dev A new bid has been placed by `bidder`.
    event BidPlaced(bytes32 indexed clusterName, address indexed bidder, uint256 bidAmount);

    /// @dev The bid has been refunded to the previous bidder, `to`.
    event BidRefunded(bytes32 indexed clusterName, address indexed to, uint256 refundedAmount);

    /// @dev The bid amount has been increased.
    event BidIncreased(bytes32 indexed clusterName, address indexed bidder, uint256 oldBidAmount, uint256 newBidAmount);

    /// @dev The bid amount has been reduced.
    event BidReduced(bytes32 indexed clusterName, address indexed bidder, uint256 oldBidAmount, uint256 newBidAmount);

    /// @dev The bid has been revoked.
    event BidRevoked(bytes32 indexed clusterName, address indexed bidder, uint256 bidAmount);

    /// @dev The bid has been accepted.
    event BidAccepted(
        bytes32 indexed clusterName, address indexed previousOwner, address indexed bidder, uint256 newBacking
    );

    /// @dev The bid timelock has been updated.
    event BidTimelockSet(uint256 newBidTimelock);

    /// @dev The minimum bid increment has been set.
    event MinBidIncrementSet(uint256 newMinBidIncrement);

    /// @dev `amount` has been withdrawn from.
    event NativeWithdrawn(address to, uint256 amount);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The contract address must have at least 4 leading zero bytes.
    error ContractAddressOverflow();

    /// @dev The name is has already been registered.
    error NameAlreadyRegistered();

    /// @dev The name is not registered.
    error NameNotRegistered();

    /// @dev The `clusterName` is invalid.
    error InvalidName();

    /// @dev The payment is insufficient.
    error Insufficient();

    /// @dev Cannot bid on a name owned by oneself.
    error SelfBid();

    /// @dev The name has no bid.
    error NoBid();

    /// @dev The bid timelock has not passed.
    error BidTimelocked();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the contract, seting the initial owner.
    function initialize(address initialOwner) public initializer onlyProxy {
        _initializeOwner(initialOwner);
        _getClustersMarketStorage().minBidIncrement = 0.0001 ether;
        _getClustersMarketStorage().bidTimelock = 30 days;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           MARKET                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Purchases the `clusterName`.
    function buy(bytes32 clusterName) public payable nonReentrant {
        uint256 contracts = _getClustersMarketStorage().contracts;
        uint256 packedInfo = _packedInfo(contracts, clusterName);
        if (_isRegistered(packedInfo)) revert NameAlreadyRegistered();

        uint256 minAnnualPrice = _minAnnualPrice(contracts);
        if (msg.value < minAnnualPrice) revert Insufficient();

        Bid storage b = _getClustersMarketStorage().bids[clusterName];
        b.lastPrice = SafeCastLib.toUint88(minAnnualPrice);
        b.lastUpdated = uint40(block.timestamp);
        b.backing = SafeCastLib.toUint88(msg.value);

        address to = MessageHubLib.senderOrSigner();
        if (_id(packedInfo) == uint256(0)) {
            _mintNext(contracts, clusterName, to);
        } else {
            _move(contracts, to, packedInfo);
        }
        emit Bought(clusterName, to, msg.value);
    }

    /// @dev Increases the backing for `clusterName`.
    function fund(bytes32 clusterName) public payable nonReentrant {
        (,, Bid storage b, address sender) = _registeredCtx(clusterName);
        uint256 oldBacking = b.backing;
        uint256 newBacking = F.rawAdd(oldBacking, msg.value);
        b.backing = SafeCastLib.toUint88(newBacking);
        emit Funded(clusterName, sender, oldBacking, newBacking);
    }

    /// @dev Flushes the ownership of `clusterName`.
    /// If `clusterName` has expired, it will be moved to the highest bidder (if any),
    /// or to a stash for reclaimmed names.
    function poke(bytes32 clusterName) public nonReentrant {
        (uint256 contracts, uint256 packedInfo, Bid storage b, address sender) = _registeredCtx(clusterName);
        _poke(contracts, packedInfo, clusterName, b, sender);
    }

    /// @dev Internal helper for poke.
    function _poke(uint256 contracts, uint256 packedInfo, bytes32 clusterName, Bid storage b, address sender)
        internal
        returns (bool moved)
    {
        (uint256 spent, uint256 newPrice) =
            _getIntegratedPrice(contracts, b.lastPrice, F.rawSub(block.timestamp, b.lastUpdated));
        uint256 backing = b.backing;

        // If out of backing (expired), transfer to highest sufficient bidder or delete registration.
        if (spent >= backing) {
            moved = true;
            (address bidder, uint256 bidAmount) = (b.bidder, b.bidAmount);
            bool hasBid = bidder != address(0);
            b.lastPrice = SafeCastLib.toUint88(_minAnnualPrice(contracts));
            b.lastUpdated = uint40(block.timestamp);
            b.backing = uint88(F.ternary(hasBid, bidAmount, 0));
            b.bidUpdated = 0;
            b.bidder = address(0);
            b.bidAmount = 0;
            _decrementTotalBidBacking(bidAmount);
            // Transfer the name to the bidder, if there's a bid, else reclaim the name.
            _move(contracts, hasBid ? bidder : _reclaimAddress(packedInfo), packedInfo);
        } else {
            b.lastPrice = SafeCastLib.toUint88(newPrice);
            b.lastUpdated = uint40(block.timestamp);
            b.backing = uint88(F.rawSub(backing, spent));
        }
        emit Poked(clusterName, sender);
    }

    /// @dev Performs a bid on `clusterName`.
    /// If the bidder is same as the previous bidder, the previous bid amount will be
    /// incremented by the `msg.value`.
    function bid(bytes32 clusterName) public payable nonReentrant {
        (uint256 contracts, uint256 packedInfo, Bid storage b, address sender) = _registeredCtx(clusterName);
        if (_owner(packedInfo) == sender) revert SelfBid();

        (address oldBidder, uint256 oldBidAmount) = (b.bidder, b.bidAmount);
        if (sender == oldBidder) {
            uint256 newBidAmount = F.rawAdd(oldBidAmount, msg.value);
            b.bidUpdated = uint40(block.timestamp);
            b.bidAmount = SafeCastLib.toUint88(newBidAmount);
            _incrementTotalBidBacking(msg.value);
            emit BidIncreased(clusterName, sender, oldBidAmount, newBidAmount);
            _poke(contracts, packedInfo, clusterName, b, sender);
        } else {
            uint256 thres = F.rawAdd(minBidIncrement(), oldBidAmount);
            if (msg.value < F.max(_minAnnualPrice(contracts), thres)) revert Insufficient();
            b.bidUpdated = uint40(block.timestamp);
            b.bidder = sender;
            b.bidAmount = SafeCastLib.toUint88(msg.value);
            _incrementTotalBidBacking(F.rawSub(msg.value, oldBidAmount));
            emit BidPlaced(clusterName, sender, msg.value);
            _poke(contracts, packedInfo, clusterName, b, sender);
            SafeTransferLib.forceSafeTransferETH(oldBidder, oldBidAmount);
            emit BidRefunded(clusterName, oldBidder, oldBidAmount);
        }
    }

    /// @dev Reduces the bid on `clusterName` by `delta`.
    /// If `delta` is equal to to greater than the current bid, revokes the bid.
    /// Only the bidder can reduce their own bid, after `bidTimelock()` has passed.
    function reduceBid(bytes32 clusterName, uint256 delta) public nonReentrant {
        (uint256 contracts, uint256 packedInfo, Bid storage b, address sender) = _registeredCtx(clusterName);
        if (block.timestamp < F.rawAdd(b.bidUpdated, bidTimelock())) revert BidTimelocked();
        if (b.bidder != sender) revert Unauthorized();

        if (!_poke(contracts, packedInfo, clusterName, b, sender)) {
            uint256 oldBidAmount = b.bidAmount;
            if (delta >= oldBidAmount) {
                b.bidUpdated = 0;
                b.bidder = address(0);
                b.bidAmount = 0;
                _decrementTotalBidBacking(oldBidAmount);
                SafeTransferLib.forceSafeTransferETH(sender, oldBidAmount);
                emit BidRevoked(clusterName, sender, oldBidAmount);
            } else {
                uint256 newBidAmount = F.rawSub(oldBidAmount, delta);
                if (newBidAmount < _minAnnualPrice(contracts)) revert Insufficient();
                b.bidAmount = uint88(newBidAmount);
                b.bidUpdated = uint40(block.timestamp);
                _decrementTotalBidBacking(delta);
                SafeTransferLib.forceSafeTransferETH(sender, delta);
                emit BidReduced(clusterName, sender, oldBidAmount, newBidAmount);
            }
        }
    }

    /// @dev Accepts the bid for `clusterName`.
    function acceptBid(bytes32 clusterName) public nonReentrant {
        (uint256 contracts, uint256 packedInfo, Bid storage b, address sender) = _registeredCtx(clusterName);
        (address bidder, uint256 bidAmount) = (b.bidder, b.bidAmount);
        if (bidder == address(0)) revert NoBid();
        if (_owner(packedInfo) != sender) revert Unauthorized();

        b.lastPrice = SafeCastLib.toUint88(_minAnnualPrice(contracts));
        b.lastUpdated = uint40(block.timestamp);
        b.backing = uint88(bidAmount);
        b.bidUpdated = 0;
        b.bidder = address(0);
        b.bidAmount = 0;
        _decrementTotalBidBacking(bidAmount);
        _move(contracts, bidder, packedInfo);
        emit BidAccepted(clusterName, sender, bidder, bidAmount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the consolidated info about the `clusterName`.
    function nameInfo(bytes32 clusterName) public view returns (NameInfo memory info) {
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        uint256 contracts = $.contracts;
        uint256 packedInfo = _packedInfo(contracts, clusterName);
        info.id = _id(packedInfo);
        info.owner = _owner(packedInfo);
        info.startTimestamp = _startTimestamp(packedInfo);
        info.isRegistered = _isRegistered(packedInfo);
        Bid memory b = $.bids[clusterName];
        info.lastPrice = b.lastPrice;
        info.lastUpdated = b.lastUpdated;
        info.bidAmount = b.bidAmount;
        info.bidUpdated = b.bidUpdated;
        info.bidder = b.bidder;
        info.backing = b.backing;
        if (info.lastUpdated == uint256(0)) {
            (uint256 initialTimestamp, uint256 initialBacking) = _initialData(contracts, clusterName);
            info.lastPrice = SafeCastLib.toUint88(_minAnnualPrice(contracts));
            info.lastUpdated = SafeCastLib.toUint40(initialTimestamp);
            info.backing = SafeCastLib.toUint88(initialBacking);
        }
    }

    /// @dev Returns if the `clusterName` is registered.
    function isRegistered(bytes32 clusterName) public view returns (bool) {
        return _isRegistered(_packedInfo(_getClustersMarketStorage().contracts, clusterName));
    }

    /// @dev Returns the pricing contract.
    function pricingContract() public view returns (address) {
        return address(uint160((_getClustersMarketStorage().contracts << 128) >> 128));
    }

    /// @dev Returns the nft contract.
    function nftContract() public view returns (address) {
        return address(uint160(_getClustersMarketStorage().contracts >> 128));
    }

    /// @dev Returns the minimum bid increment.
    function minBidIncrement() public view returns (uint256) {
        return _getClustersMarketStorage().minBidIncrement;
    }

    /// @dev Returns the bid timelock.
    function bidTimelock() public view returns (uint256) {
        return _getClustersMarketStorage().bidTimelock;
    }

    /// @dev Returns the total amount of bid backing.
    function totalBidBacking() public view returns (uint256) {
        return _getClustersMarketStorage().totalBidBacking;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner to set the pricing contract.
    function setPricingContract(address newContract) public onlyOwner {
        uint256 c = uint256(uint160(newContract));
        if (c != uint128(c)) revert ContractAddressOverflow();
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        $.contracts = (($.contracts >> 128) << 128) | c;
        emit PricingContractSet(newContract);
    }

    /// @dev Allows the owner to set the NFT contract.
    function setNFTContract(address newContract) public onlyOwner {
        uint256 c = uint256(uint160(newContract));
        if (c != uint128(c)) revert ContractAddressOverflow();
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        $.contracts = (($.contracts << 128) >> 128) | (c << 128);
        emit NFTContractSet(newContract);
    }

    /// @dev Allows the owner to set the minimum bid increment.
    function setMinBidIncrement(uint256 newMinBidIncrement) public onlyOwner {
        _getClustersMarketStorage().minBidIncrement = SafeCastLib.toUint88(newMinBidIncrement);
        emit MinBidIncrementSet(newMinBidIncrement);
    }

    /// @dev Allows the owner to set the bid timelock.
    function setBidTimelock(uint256 newBidTimelock) public onlyOwner {
        _getClustersMarketStorage().bidTimelock = SafeCastLib.toUint32(newBidTimelock);
        emit BidTimelockSet(newBidTimelock);
    }

    /// @dev Allows the owner to withdraw the protocol accrual.
    function withdrawNative(address to, uint256 amount) public onlyOwner {
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        uint256 withdrawable = F.zeroFloorSub(address(this).balance, $.totalBidBacking);
        uint256 clampedAmount = F.min(amount, withdrawable);
        SafeTransferLib.forceSafeTransferETH(to, clampedAmount);
        emit NativeWithdrawn(to, clampedAmount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 CONTRACT INTERNAL HELPERS                  */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    // Note:
    // - `packedInfo` is an uint256 that contains the NFT `id` along with it's owner.
    //   Bits Layout:
    //   - [0..39]   `id`.
    //   - [40..79]  `startTimestamp`.
    //   - [96..255] `owner`.
    // - `contracts` is a uint256 that contains both the pricing contract and NFT contract.
    //   By passing around packed variables, we save gas on stack ops and avoid stack-too-deep.

    /// @dev Returns the packed info of `clusterName`.
    function _packedInfo(uint256 contracts, bytes32 clusterName) internal view returns (uint256 result) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, 0xffbda1c3) // `infoOf(bytes32)`.
            mstore(0x20, clusterName)
            let success := staticcall(gas(), shr(128, contracts), 0x1c, 0x24, m, 0x60)
            if iszero(and(gt(returndatasize(), 0x5f), success)) { revert(codesize(), 0x00) }
            result := or(shl(96, mload(add(m, 0x20))), or(shl(40, mload(add(m, 0x40))), mload(m)))
        }
    }

    /// @dev Returns the `initialTimestamp` and `initialBacking` of `clusterName`.
    function _initialData(uint256 contracts, bytes32 clusterName)
        internal
        view
        returns (uint256 initialTimestamp, uint256 initialBacking)
    {
        assembly ("memory-safe") {
            mstore(0x00, 0x4894cb4c) // `initialData(bytes32)`.
            mstore(0x20, clusterName)
            let success := staticcall(gas(), shr(128, contracts), 0x1c, 0x24, 0x00, 0x40)
            if iszero(and(gt(returndatasize(), 0x3f), success)) { revert(codesize(), 0x00) }
            initialTimestamp := mload(0x00)
            initialBacking := mload(0x20)
        }
    }

    /// @dev Returns the owner of `packedInfo`.
    function _owner(uint256 packedInfo) internal pure returns (address) {
        return address(uint160(packedInfo >> 96));
    }

    /// @dev Returns the start timestamp of `packedInfo`.
    function _startTimestamp(uint256 packedInfo) internal pure returns (uint256) {
        return uint40(packedInfo >> 40);
    }

    /// @dev Returns the id of `packedInfo`.
    function _id(uint256 packedInfo) internal pure returns (uint256) {
        return uint40(packedInfo);
    }

    /// @dev Returns if the name has been registered.
    function _isRegistered(uint256 packedInfo) internal pure returns (bool result) {
        // Returns whether the owner is any address greater than `0..256`.
        return packedInfo >> 96 > 0x100;
    }

    /// @dev Returns the address which the name is to be reclaimed into.
    /// This is to allow for a world where we have more than 4294967295 cluster names.
    function _reclaimAddress(uint256 packedInfo) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := add(1, and(0xff, packedInfo))
        }
    }

    /// @dev Calls `mintNext` on the nft contract.
    function _mintNext(uint256 contracts, bytes32 clusterName, address to) internal {
        assembly ("memory-safe") {
            mstore(0x00, 0x5dcdcf970000000000000000) // `mintNext(bytes32,address)`.
            mstore(0x18, clusterName)
            mstore(0x38, shr(96, shl(96, to)))
            if iszero(call(gas(), shr(128, contracts), 0, 0x14, 0x44, codesize(), 0x00)) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize()) // Bubble up the revert.
            }
            mstore(0x38, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Calls `conduitSafeTransfer` on the nft contract.
    function _move(uint256 contracts, address to, uint256 packedInfo) internal {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x7ac99264) // `conduitSafeTransfer(address,address,uint256)`.
            mstore(add(m, 0x20), shr(96, packedInfo)) // `from`.
            mstore(add(m, 0x40), shr(96, shl(96, to))) // `to`.
            mstore(add(m, 0x60), and(0xffffffffff, packedInfo)) // `id`.
            if iszero(call(gas(), shr(128, contracts), 0, add(m, 0x1c), 0x64, codesize(), 0x00)) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize()) // Bubble up the revert.
            }
        }
    }

    /// @dev Returns the minimum annual price.
    function _minAnnualPrice(uint256 contracts) internal view returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(0x00, 0x360c93dd) // `minAnnualPrice()`.
            let success := staticcall(gas(), shr(128, shl(128, contracts)), 0x1c, 0x04, 0x00, 0x20)
            if iszero(and(gt(returndatasize(), 0x1f), success)) { revert(codesize(), 0x00) }
            result := mload(0x00)
        }
    }

    /// @dev Returns the integrated price.
    function _getIntegratedPrice(uint256 contracts, uint256 lastUpdatedPrice, uint256 secondsSinceUpdate)
        internal
        view
        returns (uint256 spent, uint256 price)
    {
        assembly ("memory-safe") {
            mstore(0x00, 0x4e34478d0000000000000000) // `getIntegratedPrice(uint256,uint256)`.
            mstore(0x18, lastUpdatedPrice)
            mstore(0x38, secondsSinceUpdate)
            let success := staticcall(gas(), shr(128, shl(128, contracts)), 0x14, 0x44, 0x00, 0x40)
            if iszero(and(gt(returndatasize(), 0x3f), success)) { revert(codesize(), 0x00) }
            spent := mload(0x00)
            price := mload(0x20)
            mstore(0x38, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Helper for returning the context variables for a registered `clusterName`.
    function _registeredCtx(bytes32 clusterName)
        internal
        returns (uint256 contracts, uint256 packedInfo, Bid storage b, address sender)
    {
        contracts = _getClustersMarketStorage().contracts;
        packedInfo = _packedInfo(contracts, clusterName);
        if (!_isRegistered(packedInfo)) revert NameNotRegistered();
        b = _getClustersMarketStorage().bids[clusterName];
        if (b.lastUpdated == uint256(0)) {
            (uint256 initialTimestamp, uint256 initialBacking) = _initialData(contracts, clusterName);
            b.lastPrice = SafeCastLib.toUint88(_minAnnualPrice(contracts));
            b.lastUpdated = SafeCastLib.toUint40(initialTimestamp);
            b.backing = SafeCastLib.toUint88(initialBacking);
        }
        sender = MessageHubLib.senderOrSigner();
    }

    /// @dev Increments the total bid backing.
    function _incrementTotalBidBacking(uint256 amount) internal {
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        $.totalBidBacking = SafeCastLib.toUint88(uint256($.totalBidBacking) + amount);
    }

    /// @dev Decrements the total bid backing.
    function _decrementTotalBidBacking(uint256 amount) internal {
        ClustersMarketStorage storage $ = _getClustersMarketStorage();
        $.totalBidBacking = uint88(uint256($.totalBidBacking) - amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
