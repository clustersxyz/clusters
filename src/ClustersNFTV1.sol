// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibMap} from "solady/utils/LibMap.sol";
import {LibBit} from "solady/utils/LibBit.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {MessageHubLibV1 as MessageHubLib} from "clusters/MessageHubLibV1.sol";

/// @title ClustersNFTV1
/// @notice Each name is represented by a unique NFT.
/// Once a name is minted, it cannot be changed.
/// For simplicity, this contract does not support burning.
contract ClustersNFTV1 is UUPSUpgradeable, Initializable, ERC721, Ownable, EnumerableRoles {
    using LibMap for LibMap.Uint40Map;
    using DynamicArrayLib for uint256[];

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev A struct to hold the mint information for `mintNext`.
    struct Mint {
        // The name to be minted.
        bytes32 clusterName;
        // The mint recipient.
        address to;
        // The initial timestamp for the market pricing integral.
        uint256 initialTimestamp;
        // The initial backing for the market.
        uint256 initialBacking;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Admin.
    uint256 public constant ADMIN_ROLE = 0;

    /// @dev Minter.
    uint256 public constant MINTER_ROLE = 1;

    /// @dev For marketplaces to transfer tokens.
    uint256 public constant CONDUIT_ROLE = 2;

    /// @dev Cluster additional data setter.
    uint256 public constant ADDITIONAL_DATA_SETTER_ROLE = 3;

    /// @dev The maximum role.
    uint256 public constant MAX_ROLE = 3;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    // Note: Solady's ERC721 has auxiliary data.
    //
    // - `_getExtraData(uint256 id) internal view virtual returns (uint96 result)`.
    //   For names of 1 to 12 bytes, we will store it in the per-token `extraData`.
    //   Otherwise, we will store it in the `fullName` mapping.
    //
    // - `_getAux(address owner) internal view virtual returns (uint224 result)`.
    //   We will use this 224 bits to store the default name id, as well as
    //   the ids of the tokens `0,1,2,3,4` of the owner.

    /// @dev The storage struct for a single name.
    struct NameData {
        // Bits Layout:
        // - [0..39]   `id`.
        // - [40..47]  `ownedIndex`.
        // - [48..87]  `startTimestamp`.
        // - [88..255] `additionalData`.
        uint256 packed;
        // Stores the owned index if it is greater than 254.
        uint256 fullOwnedIndex;
        // The initial packed data.
        uint256 initialPacked;
    }

    /// @dev The storage struct for the contract.
    struct ClustersNFTStorage {
        // Auto-incremented and used for assigning the NFT `id`, starting from 1.
        uint256 totalMinted;
        // Mapping of NFT `id` to the full `name`.
        mapping(uint256 => bytes32) fullName;
        // Mapping of NFT `owner` to their full default NFT `id`.
        mapping(address => uint256) fullDefaultId;
        // Mapping of NFT `owner` to the NFT `id`, from 5 onwards.
        mapping(address => LibMap.Uint40Map) ownedIds;
        // Mapping of `name` to the `NameData`.
        mapping(bytes32 => NameData) nameData;
        // Whether transfers, excluding mints, are paused. For bulk seeding phase.
        bool paused;
        // Contract for rendering the token URI.
        address tokenURIRenderer;
    }

    /// @dev Returns the storage struct for the contract.
    function _getClustersNFTStorage() internal pure returns (ClustersNFTStorage storage $) {
        assembly ("memory-safe") {
            // `uint72(bytes9(keccak256("Clusters.ClustersNFTStorage")))`.
            $.slot := 0xda8b89020ecb842518 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The token URI renderer is set.
    event TokenURIRendererSet(address renderer);

    /// @dev The default id of `owner` has been set to `id`.
    event DefaultIdSet(address indexed owner, uint256 id);

    /// @dev The paused status of the contract is updated.
    event PausedSet(bool paused);

    /// @dev The linked address of `clusterName` is updated.
    event LinkedAddressSet(bytes32 indexed clusterName, address indexed linkedAddress);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The name cannot be `bytes32(0)`.
    error NameIsZero();

    /// @dev The name already exists.
    error NameAlreadyExists();

    /// @dev The query index is out of bounds.
    error IndexOutOfBounds();

    /// @dev Cannot mint nothing.
    error NothingToMint();

    /// @dev Transfers are paused.
    error Paused();

    /// @dev The name is invalid.
    error InvalidName();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the contract, seting the initial owner.
    function initialize(address initialOwner) public initializer onlyProxy {
        _initializeOwner(initialOwner);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                            META                            */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name and version of the contract.
    function contactNameAndVersion() public pure returns (string memory, string memory) {
        return (name(), "1.0.0");
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC721 METADATA                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name of the contract.
    function name() public pure override returns (string memory) {
        return "Clusters";
    }

    /// @dev Returns the symbol of the contract.
    function symbol() public pure override returns (string memory) {
        return "CLUSTERS";
    }

    /// @dev Returns the token URI for the given `id`.
    /// This method may perform a direct return via inline assembly
    /// for efficiency, and thus must not be called internally.
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_exists(id)) revert TokenDoesNotExist();
        address renderer = _getClustersNFTStorage().tokenURIRenderer;
        if (renderer == address(0)) return "";
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, 0xc87b56dd) // `tokenURI(uint256)`.
            mstore(0x20, id)
            if iszero(staticcall(gas(), renderer, 0x1c, 0x24, 0x00, 0x00)) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            returndatacopy(m, 0x00, returndatasize())
            return(m, returndatasize())
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     ERC721 ENUMERABLE                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the total number of NFTs.
    function totalSupply() public view returns (uint256) {
        return _getClustersNFTStorage().totalMinted;
    }

    /// @dev Returns the token ID by the given `index`.
    function tokenByIndex(uint256 index) public view returns (uint256) {
        if (index >= totalSupply()) revert IndexOutOfBounds();
        unchecked {
            return index + 1;
        }
    }

    /// @dev Returns the token IDs of `owner`.
    /// This method may exceed the block gas limit if the owner has too many tokens.
    /// This method performs a direct return via inline assembly for efficiency,
    /// and is thus marked as external.
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 n = balanceOf(owner);
        uint256[] memory result = DynamicArrayLib.malloc(n);
        unchecked {
            for (uint256 i; i != n; ++i) {
                result.set(i, _getId(owner, i));
            }
        }
        DynamicArrayLib.directReturn(result);
    }

    /// @dev Returns the token ID of `owner` at `i`.
    function tokenOfOwnerByIndex(address owner, uint256 i) public view returns (uint256) {
        if (i > balanceOf(owner)) revert IndexOutOfBounds();
        return _getId(owner, i);
    }

    /// @dev ERC-165 override.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // 0x780e9d63 is the interface ID for ERC721Enumerable.
        return LibBit.or(super.supportsInterface(interfaceId), interfaceId == 0x780e9d63);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name of token `id`.
    /// Returns zero if it does not exist.
    function nameOf(uint256 id) public view returns (bytes32) {
        uint96 truncatedName = _getExtraData(id);
        if (truncatedName != 0) return bytes12(truncatedName);
        return _getClustersNFTStorage().fullName[id];
    }

    /// @dev Returns the token `id`, `owner`, and `startTimestamp` of `clusterName`.
    /// All values are zero if it does not exist.
    /// Used by the Market.
    function infoOf(bytes32 clusterName) public view returns (uint256 id, address owner, uint256 startTimestamp) {
        uint256 p = _getClustersNFTStorage().nameData[clusterName].packed;
        id = uint40(p);
        owner = _ownerOf(id);
        startTimestamp = uint40(p >> 48);
    }

    /// @dev Returns the token URI renderer contract.
    function tokenURIRenderer() public view returns (address) {
        return _getClustersNFTStorage().tokenURIRenderer;
    }

    /// @dev Returns whether token transfers are paused.
    function isPaused() public view returns (bool) {
        return _getClustersNFTStorage().paused;
    }

    /// @dev Returns the initial additional data of `clusterName`.
    function initialData(bytes32 clusterName) public view returns (uint256 initialTimestamp, uint256 initialBacking) {
        NameData memory d = _getClustersNFTStorage().nameData[clusterName];
        uint256 p = d.packed;
        if (p >> 248 != uint256(0)) p = d.initialPacked;
        initialBacking = p >> (88 + 40);
        initialTimestamp = uint40(p >> 88);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                  LINKED ADDRESS FUNCTIONS                  */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the additional data of `clusterName`.
    /// Does not revert even if `clusterName` does not exist,
    /// so that we can have the freedom to access before the name exists.
    function setLinkedAddress(bytes32 clusterName, address newLinkedAddress) public {
        NameData storage d = _getClustersNFTStorage().nameData[clusterName];
        uint256 p = d.packed;
        if (MessageHubLib.senderOrSigner() != _ownerOf(uint40(p))) revert Unauthorized();
        if (p >> 248 == uint256(0)) d.initialPacked = p;
        assembly ("memory-safe") {
            mstore(0x0b, p)
            mstore(0x00, newLinkedAddress)
            mstore8(0x0b, 1)
            sstore(d.slot, mload(0x0b))
        }
        emit LinkedAddressSet(clusterName, newLinkedAddress);
    }

    /// @dev Returns the linked address of `clusterName`.
    function linkedAddress(bytes32 clusterName) public view returns (address) {
        NameData memory d = _getClustersNFTStorage().nameData[clusterName];
        uint256 p = d.packed;
        return p >> 248 == uint256(0) ? address(0) : address(uint160(p >> 88));
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          MINTING                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Mints a new NFT with the given `clusterName` and assigns it to `to`.
    /// Used by the Market.
    function mintNext(bytes32 clusterName, address to) public onlyOwnerOrRole(MINTER_ROLE) returns (uint256 id) {
        id = _mintNext(clusterName, to, 0, 0);
    }

    /// @dev Mints new NFTs with the given `clusterNames` and assigns them to `to`.
    function mintNext(Mint[] calldata mints) public onlyOwnerOrRole(MINTER_ROLE) returns (uint256 startId) {
        if (mints.length == uint256(0)) revert NothingToMint();
        unchecked {
            for (uint256 i; i != mints.length; ++i) {
                Mint calldata mint;
                assembly ("memory-safe") {
                    mint := add(mints.offset, shl(7, i))
                }
                uint256 id = _mintNext(mint.clusterName, mint.to, mint.initialTimestamp, mint.initialBacking);
                if (i == uint256(0)) startId = id;
            }
        }
    }

    /// @dev Mints a new NFT with the given `clusterName` and assigns it to `to`.
    function _mintNext(bytes32 clusterName, address to, uint256 initialTimestamp, uint256 initialBacking)
        internal
        returns (uint256 id)
    {
        if (!_isValidName(clusterName)) revert InvalidName();
        ClustersNFTStorage storage $ = _getClustersNFTStorage();

        NameData storage d = $.nameData[clusterName];
        if (uint40(d.packed) != 0) revert NameAlreadyExists();

        unchecked {
            id = ++$.totalMinted;
        }
        uint96 truncatedName = uint96(bytes12(clusterName));
        if (bytes12(truncatedName) != clusterName) {
            $.fullName[id] = clusterName;
            truncatedName = 0;
        }

        require((((id | initialTimestamp) >> 40) | (initialBacking >> 88)) == uint256(0));

        // Construct the new `p` with `id`, the timestamp, with `additionalData`
        // initialized with `initialTimestamp` and `initialBacking`.
        uint256 p = (((initialBacking << 40) | initialTimestamp) << 88) | id | (block.timestamp << 48);

        uint256 ownedIndex = balanceOf(to);
        if (ownedIndex >= 0xff) {
            d.packed = p;
            d.fullOwnedIndex = ownedIndex;
        } else {
            d.packed = _setByte(p, 26, 0xff ^ ownedIndex);
        }
        _setId(to, ownedIndex, uint40(id));

        _mintAndSetExtraDataUnchecked(to, id, truncatedName);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC721 OVERRIDES                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev This affects the `safeTransferFrom` variants too.
    function transferFrom(address from, address to, uint256 id) public payable override {
        _transfer(MessageHubLib.senderOrSigner(), from, to, id);
    }

    /// @dev Override for `approve`.
    function approve(address account, uint256 id) public payable override {
        _approve(MessageHubLib.senderOrSigner(), account, id);
    }

    /// @dev Override for `setApprovalForAll`.
    function setApprovalForAll(address operator, bool isApproved) public override {
        _setApprovalForAll(MessageHubLib.senderOrSigner(), operator, isApproved);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                    DEFAULT ID FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the default id of the caller. The caller must own the `id`.
    function setDefaultId(uint256 id) public {
        address sender = MessageHubLib.senderOrSigner();
        if (_ownerOf(id) != sender) revert Unauthorized();
        uint224 aux = (_getAux(sender) >> 24) << 24;
        if (id >= 0xffffff) {
            _setAux(sender, aux);
            _getClustersNFTStorage().fullDefaultId[sender] = id;
        } else {
            _setAux(sender, aux | uint224(id));
        }
        emit DefaultIdSet(sender, id);
    }

    /// @dev Returns the default id of `owner`.
    /// If the owner does not own their default id,
    /// returns one of the ids owned by `owner`.
    /// If the owner does not have any id, returns `0`.
    function defaultId(address owner) public view returns (uint256) {
        if (balanceOf(owner) == 0) return 0;
        uint256 result = _getAux(owner) & 0xffffff;
        result = result == uint256(0) ? _getClustersNFTStorage().fullDefaultId[owner] : 0xffffff ^ result;
        if (result != 0) if (_ownerOf(result) == owner) return result;
        return _getId(owner, 0);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the token URI renderer contract.
    function setTokenURIRenderer(address renderer) public onlyOwnerOrRole(ADMIN_ROLE) {
        _getClustersNFTStorage().tokenURIRenderer = renderer;
        emit TokenURIRendererSet(renderer);
    }

    /// @dev Sets the paused status of the contract.
    function setPaused(bool paused) public onlyOwnerOrRole(ADMIN_ROLE) {
        _getClustersNFTStorage().paused = paused;
        emit PausedSet(paused);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      CONDUIT TRANSFER                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Enables the marketplace to transfer the NFT. This is used when a NFT is outbidded.
    /// Used by the Market.
    function conduitSafeTransfer(address from, address to, uint256 id) public onlyRole(CONDUIT_ROLE) {
        _safeTransfer(from, to, id); // We don't need data, since this NFT doesn't use it.
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the `i`-th byte of `x` to `b` and returns the result.
    function _setByte(uint256 x, uint256 i, uint256 b) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(0x00, x)
            mstore8(i, b)
            result := mload(0x00)
        }
    }

    /// @dev Returns the token of `owner` at index `i`.
    function _getId(address owner, uint256 i) internal view returns (uint40) {
        unchecked {
            if (i >= 5) {
                return _getClustersNFTStorage().ownedIds[owner].get(i - 5);
            } else {
                return uint40(_getAux(owner) >> (24 + i * 40));
            }
        }
    }

    /// @dev Sets the token of `owner` at index `i`.
    function _setId(address owner, uint256 i, uint40 id) internal {
        unchecked {
            if (i >= 5) {
                _getClustersNFTStorage().ownedIds[owner].set(i - 5, id);
            } else {
                uint224 aux = _getAux(owner);
                uint256 o = 24 + i * 40;
                assembly ("memory-safe") {
                    aux := xor(aux, shl(o, and(0xffffffffff, xor(shr(o, aux), id))))
                }
                _setAux(owner, aux);
            }
        }
    }

    /// @dev Returns if the name is a valid cluster name.
    function _isValidName(bytes32 clusterName) internal pure returns (bool result) {
        uint256 m;
        assembly ("memory-safe") {
            m := mload(0x40) // Cache the free memory pointer.
        }
        string memory s = LibString.fromSmallString(clusterName);
        bool allValidChars = LibString.is7BitASCII(s, 0x7fffffe8000000003ff200000000000); // `[a-z0-9_-]+`.
        assembly ("memory-safe") {
            let notNormalized := xor(mload(add(0x20, s)), clusterName)
            result := iszero(or(or(iszero(allValidChars), iszero(clusterName)), notNormalized))
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Used for maintaining the enumeration of owned tokens.
    function _afterTokenTransfer(address from, address to, uint256 id) internal override {
        // If it's a mint, or self-transfer, early return.
        // We don't need to care about the burn case.
        if (LibBit.or(from == address(0), from == to)) return;

        ClustersNFTStorage storage $ = _getClustersNFTStorage();
        if ($.paused) revert Paused();
        NameData storage d = $.nameData[nameOf(id)];
        uint256 p = d.packed;
        // Update the timestamp in `p`.
        p ^= (((p >> 48) ^ block.timestamp) & 0xffffffffff) << 48;

        // Remove token from owner enumeration.
        uint256 j = balanceOf(from); // The last token index.
        uint256 i = uint8(bytes32(p)[26]);
        i = i == uint256(0) ? d.fullOwnedIndex : 0xff ^ i; // Current token index.
        if (i != j) {
            uint40 lastTokenId = _getId(from, j);
            _setId(from, i, lastTokenId);
            NameData storage e = $.nameData[nameOf(lastTokenId)];
            if (i >= 0xff) {
                e.packed = _setByte(e.packed, 26, 0);
                e.fullOwnedIndex = i;
            } else {
                e.packed = _setByte(e.packed, 26, 0xff ^ i);
            }
        }
        // Add token to owner enumeration.
        unchecked {
            i = balanceOf(to) - 1; // The new owned index of `id`.
            _setId(to, i, uint40(id));
            if (i >= 0xff) {
                d.packed = _setByte(p, 26, 0);
                d.fullOwnedIndex = i;
            } else {
                d.packed = _setByte(p, 26, 0xff ^ i);
            }
        }
    }

    /// @dev For UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
