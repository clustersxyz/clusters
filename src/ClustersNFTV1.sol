// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {LibMap} from "solady/utils/LibMap.sol";
import {LibBit} from "solady/utils/LibBit.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {EnumerableRoles} from "clusters/EnumerableRoles.sol";
import {MessageHubLibV1 as MessageHubLib} from "clusters/MessageHubLibV1.sol";

/// @title ClustersNFTV1
/// @notice Each cluster name is represented by a unique NFT.
///         Once a cluster name is minted, it cannot be changed.
///         For simplicity, this contract does not support burning.
contract ClustersNFTV1 is UUPSUpgradeable, Initializable, ERC721, Ownable, EnumerableRoles {
    using LibMap for LibMap.Uint40Map;
    using DynamicArrayLib for uint256[];

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Admin.
    uint8 public constant ADMIN_ROLE = 0;

    /// @dev Minter.
    uint8 public constant MINTER_ROLE = 1;

    /// @dev Cluster additional data setter.
    uint8 public constant CLUSTERS_ADDITIONAL_DATA_SETTER_ROLE = 2;

    /// @dev For marketplaces to transfer tokens.
    uint8 public constant CLUSTERS_CONDUIT_ROLE = 3;

    /// @dev The maximum role.
    uint8 public constant MAX_ROLE = 3;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    // Note: Solady's ERC721 has auxiliary data.
    //
    // - `_getExtraData(uint256 id) internal view virtual returns (uint96 result)`.
    //   For cluster names of 1 to 12 bytes, we will store it in the per-token `extraData`.
    //   Otherwise, we will store it in the `fullClusterName` mapping.
    //
    // - `_getAux(address owner) internal view virtual returns (uint224 result)`.
    //   We will use this 224 bits to store the default cluster id.

    /// @dev The storage struct for a single cluster.
    struct ClustersData {
        // Stores the `id`, `ownedIndex` and `additionalData`.
        uint256 packed;
        // Stores the owned index if it is greater than 254.
        uint256 fullOwnedIndex;
    }

    /// @dev The storage struct for the contract.
    struct ClustersNFTStorage {
        // Auto-incremented and used for assigning the NFT `id`, starting from 1.
        uint256 totalMinted;
        // Mapping of NFT `id` to the full `clusterName`.
        mapping(uint256 => bytes32) fullClusterName;
        // Mapping of NFT `owner` to the NFT `id`. For onchain enumeration.
        mapping(address => LibMap.Uint40Map) ownedIds;
        // Mapping of `clusterName` to the `ClustersData`.
        mapping(bytes32 => ClustersData) clusterData;
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

    /// @dev The default cluster id of `owner` has been set to `id`.
    event DefaultClusterIdSet(address indexed owner, uint256 id);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The lengths of the arrays do not match.
    error ArrayLengthsMismatch();

    /// @dev The cluster name cannot be `bytes32(0)`.
    error ClusterNameIsZero();

    /// @dev The cluster name already exists.
    error ClusterNameAlreadyExists();

    /// @dev The query index is out of bounds.
    error IndexOutOfBounds();

    /// @dev Cannot mint nothing.
    error NothingToMint();

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
    ///      This method may perform a direct return via inline assembly
    ///      for efficiency, and thus must not be called internally.
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
    ///      This method may exceed the block gas limit if the owner has too many tokens.
    ///      This method performs a direct return via inline assembly for efficiency,
    ///      and is thus marked as external.
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 n = balanceOf(owner);
        uint256[] memory result = DynamicArrayLib.malloc(n);
        LibMap.Uint40Map storage ownedIds = _getClustersNFTStorage().ownedIds[owner];
        unchecked {
            for (uint256 i; i != n; ++i) {
                result.set(i, ownedIds.get(i));
            }
        }
        DynamicArrayLib.directReturn(result);
    }

    /// @dev Returns the token ID of `owner` at `i`.
    function tokenOfOwnerByIndex(address owner, uint256 i) public view returns (uint256) {
        if (i > balanceOf(owner)) revert IndexOutOfBounds();
        return _getClustersNFTStorage().ownedIds[owner].get(i);
    }

    /// @dev ERC-165 override.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // 0x780e9d63 is the interface ID for ERC721Enumerable.
        return LibBit.or(super.supportsInterface(interfaceId), interfaceId == 0x780e9d63);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the cluster name of token `id`.
    ///      Reverts if `id` does not exist.
    function clusterNameOf(uint256 id) public view returns (bytes32 result) {
        uint96 truncatedName = _getExtraData(id);
        if (truncatedName != 0) return bytes12(truncatedName);
        result = _getClustersNFTStorage().fullClusterName[id];
        if (result == bytes32(0)) revert TokenDoesNotExist();
    }

    /// @dev Returns the token ID of `clusterName`.
    ///      Reverts if `clusterName` does not exist.
    function idOf(bytes32 clusterName) public view returns (uint256 result) {
        result = _getId(_getClustersNFTStorage().clusterData[clusterName]);
        if (result == uint256(0)) revert TokenDoesNotExist();
    }

    /// @dev Returns the token URI renderer contract.
    function tokenURIRenderer() public view returns (address) {
        return _getClustersNFTStorage().tokenURIRenderer;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*             CLUSTER ADDITIONAL DATA FUNCTIONS              */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the additional data of token `id`.
    function clusterAdditionalData(uint256 id) public view virtual returns (uint208) {
        return clusterAdditionalData(clusterNameOf(id));
    }

    /// @dev Returns the additional data of cluster `clusterName`.
    function clusterAdditionalData(bytes32 clusterName) public view virtual returns (uint208) {
        ClustersData storage cd = _getClustersNFTStorage().clusterData[clusterName];
        if (_getId(cd) == uint256(0)) revert TokenDoesNotExist();
        return _getAdditionalData(cd);
    }

    /// @dev Sets the additional data of token `id`.
    function setClusterAdditionalData(uint256 id, uint208 additionalData)
        public
        virtual
        onlyRole(CLUSTERS_ADDITIONAL_DATA_SETTER_ROLE)
    {
        setClusterAdditionalData(clusterNameOf(id), additionalData);
    }

    /// @dev Sets the additional data of cluster `clusterName`.
    function setClusterAdditionalData(bytes32 clusterName, uint208 additionalData)
        public
        virtual
        onlyRole(CLUSTERS_ADDITIONAL_DATA_SETTER_ROLE)
    {
        ClustersData storage cd = _getClustersNFTStorage().clusterData[clusterName];
        if (_getId(cd) == uint256(0)) revert TokenDoesNotExist();
        _setAdditionalData(cd, additionalData);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          MINTING                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Mints a new NFT with the given `clusterName` and assigns it to `to`.
    function mintNext(bytes32 clusterName, address to) public onlyOwnerOrRole(MINTER_ROLE) returns (uint256 id) {
        id = _mintNext(clusterName, to);
    }

    /// @dev Mints new NFTs with the given `clusterNames` and assigns them to `to`.
    function mintNext(bytes32[] calldata clusterNames, address[] calldata to)
        public
        onlyOwnerOrRole(MINTER_ROLE)
        returns (uint256 startTokenId)
    {
        if (clusterNames.length != to.length) revert ArrayLengthsMismatch();
        if (clusterNames.length == uint256(0)) revert NothingToMint();
        startTokenId = _mintNext(_get(clusterNames, 0), _get(to, 0));
        unchecked {
            for (uint256 i = 1; i != clusterNames.length; ++i) {
                _mintNext(_get(clusterNames, i), _get(to, i));
            }
        }
    }

    /// @dev Mints a new NFT with the given `clusterName` and assigns it to `to`.
    function _mintNext(bytes32 clusterName, address to) internal returns (uint256 id) {
        if (clusterName == bytes32(0)) revert ClusterNameIsZero();
        ClustersNFTStorage storage $ = _getClustersNFTStorage();

        ClustersData storage cd = $.clusterData[clusterName];
        if (_getId(cd) != 0) revert ClusterNameAlreadyExists();

        unchecked {
            id = ++$.totalMinted;
            if (id > type(uint40).max) revert();
        }
        uint96 truncatedName = uint96(bytes12(clusterName));
        if (bytes12(truncatedName) != clusterName) {
            $.fullClusterName[id] = clusterName;
            truncatedName = 0;
        }

        uint256 ownedIndex = balanceOf(to);
        _initialize(cd, id, ownedIndex);
        $.ownedIds[to].set(ownedIndex, uint40(id));

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
    /*                DEFAULT CLUSTER ID FUNCTIONS                */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the default cluster id of the caller.
    ///      The caller must own the `id`.
    function setDefaultClusterId(uint256 id) public {
        address sender = MessageHubLib.senderOrSigner();
        if (ownerOf(id) != sender) revert Unauthorized();
        _setAux(sender, uint224(id));
        emit DefaultClusterIdSet(sender, id);
    }

    /// @dev Returns the default cluster id of `owner`.
    ///      If the owner does not own their default cluster id,
    ///      returns one of the clyster ids owned by `owner`.
    ///      If the owner does not have any cluster id, returns `0`.
    function defaultClusterId(address owner) public view returns (uint256) {
        if (balanceOf(owner) == 0) return 0;
        uint256 result = _getAux(owner);
        if (result != 0) if (_ownerOf(result) == owner) return result;
        return _getClustersNFTStorage().ownedIds[owner].get(0);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the token URI renderer contract.
    function setTokenURIRenderer(address renderer) public onlyOwnerOrRole(ADMIN_ROLE) {
        _getClustersNFTStorage().tokenURIRenderer = renderer;
        emit TokenURIRendererSet(renderer);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      CONDUIT TRANSFER                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Enables the marketplace to transfer the NFT.
    ///      This is used when a NFT is outbidded.
    function conduitSafeTransfer(address from, address to, uint256 id) public onlyRole(CLUSTERS_CONDUIT_ROLE) {
        _safeTransfer(from, to, id);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns `a[i]` without bounds checking.
    function _get(bytes32[] calldata a, uint256 i) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            result := calldataload(add(a.offset, shl(5, i)))
        }
    }

    /// @dev Returns `a[i]` without bounds checking.
    function _get(address[] calldata a, uint256 i) internal pure returns (address result) {
        assembly ("memory-safe") {
            result := calldataload(add(a.offset, shl(5, i)))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   CLUSTERS DATA HELPERS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the data.
    function _initialize(ClustersData storage data, uint256 id, uint256 ownedIndex) internal {
        if (ownedIndex <= 254) {
            data.packed = _setByte(id, 26, 0xff ^ ownedIndex);
        } else {
            data.packed = id;
            data.fullOwnedIndex = ownedIndex;
        }
    }

    /// @dev Returns the ID.
    function _getId(ClustersData storage data) internal view returns (uint40) {
        return uint40(data.packed);
    }

    /// @dev Returns the owned index.
    function _getOwnedIndex(ClustersData storage data) internal view returns (uint256) {
        uint256 ownedIndex = uint8(bytes32(data.packed)[26]);
        if (ownedIndex != 0) return 0xff ^ ownedIndex;
        return data.fullOwnedIndex;
    }

    /// @dev Sets the owned index.
    function _setOwnedIndex(ClustersData storage data, uint256 ownedIndex) internal {
        if (ownedIndex <= 254) {
            data.packed = _setByte(data.packed, 26, 0xff ^ ownedIndex);
        } else {
            data.packed = _setByte(data.packed, 26, 0);
            data.fullOwnedIndex = ownedIndex;
        }
    }

    /// @dev Sets the additional data.
    function _setAdditionalData(ClustersData storage data, uint208 additionalData) internal {
        assembly ("memory-safe") {
            mstore(0x06, sload(data.slot))
            mstore(0x00, additionalData)
            sstore(data.slot, mload(0x06))
        }
    }

    /// @dev Returns the additional data.
    function _getAdditionalData(ClustersData storage data) internal view returns (uint208) {
        return uint208(data.packed >> 48);
    }

    /// @dev Sets the `i`-th byte of `x` to `b` and returns the result.
    function _setByte(uint256 x, uint256 i, uint256 b) private pure returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(0x00, x)
            mstore8(i, b)
            result := mload(0x00)
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Used for maintaining the enumeration of owned tokens.
    function _afterTokenTransfer(address from, address to, uint256 id) internal override {
        if (LibBit.or(from == address(0), from == to)) return;
        ClustersNFTStorage storage $ = _getClustersNFTStorage();
        ClustersData storage cd = $.clusterData[clusterNameOf(id)];
        LibMap.Uint40Map storage fromOwnedIds = $.ownedIds[from];
        uint256 oldOwnedIndex = _getOwnedIndex(cd);
        uint40 lastTokenId = fromOwnedIds.get(balanceOf(from));
        fromOwnedIds.set(oldOwnedIndex, lastTokenId);
        _setOwnedIndex($.clusterData[clusterNameOf(lastTokenId)], oldOwnedIndex);
        unchecked {
            uint256 ownedIndex = balanceOf(to) - 1;
            $.ownedIds[to].set(ownedIndex, uint40(id));
            _setOwnedIndex(cd, ownedIndex);
        }
    }

    /// @dev For UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
