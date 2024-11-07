// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {LibClone} from "solady/utils/LibClone.sol";

/// @title ClustersCommunityBaseVaultBeta
/// @notice A contract to hold ERC20 and native tokens for a recipient of a community bid.
///         We'll just include this within the same file as ClustersCommunityBaseBeta,
///         since it is so tightly coupled.
contract ClustersCommunityBaseVaultBeta {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The caller must be the mothership, and the mothership must be called by the owner.
    error Unauthorized();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     WITHDRAW FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner to withdraw ERC20 tokens.
    function withdrawERC20(address mothershipCaller, address token, address to, uint256 amount) public {
        _checkMothership(mothershipCaller);
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @dev Allows the owner to withdraw native currency.
    function withdrawNative(address mothershipCaller, address to, uint256 amount) public {
        _checkMothership(mothershipCaller);
        SafeTransferLib.safeTransferETH(to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           GUARDS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Ensures that the caller is the mothership,
    ///      and that the caller of the mothership is the owner of the vault.
    function _checkMothership(address mothershipCaller) internal view {
        bytes memory args = LibClone.argsOnClone(address(this), 0x00, 0x28);
        address mothership = address(bytes20(LibClone.argLoad(args, 0x00)));
        address vaultOwner = address(bytes20(LibClone.argLoad(args, 0x14)));
        if (mothership != msg.sender) revert Unauthorized();
        if (vaultOwner != mothershipCaller) revert Unauthorized();
    }
}

/// @title ClustersCommunityBaseBeta
/// @notice The base class for the ClustersCommunityHubBeta and ClustersCommunityInitiatorBeta.
///         Having a base class helps with conciseness, since both classes share a lot of
///         common logic.
contract ClustersCommunityBaseBeta is EnumerableRoles, UUPSUpgradeable {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev A struct for passing in a community bid.
    struct BidConfig {
        // The token. If this is `address(0)`, the token will be the native token.
        address token;
        // The amount of token.
        uint256 amount;
        // The recipient of the token payment.
        address paymentRecipient;
        // The community name.
        bytes32 communityName;
        // The wallet name,
        bytes32 walletName;
        // This is the referral address. We use bytes32, as it might be multichain.
        bytes32 referralAddress;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Admin role.
    uint256 public constant ADMIN_ROLE = 0;

    /// @dev Withdrawer role.
    uint256 public constant WITHDRAWER_ROLE = 1;

    /// @dev Max role.
    uint256 public constant MAX_ROLE = 1;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         IMMUTABLES                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Address of the vault implementation.
    address internal immutable _vaultImplementation = address(new ClustersCommunityBaseVaultBeta());

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      VAULT FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the deterministic address of the vault of `vaultOwner`.
    function vaultOf(address vaultOwner) public view returns (address) {
        bytes memory args = abi.encodePacked(address(this), vaultOwner);
        bytes32 salt = keccak256(args);
        address deployer = address(this);
        return LibClone.predictDeterministicAddress(_vaultImplementation, args, salt, deployer);
    }

    /// @dev Creates a vault for `vaultOwner` if one does not exist yet.
    function createVault(address vaultOwner) public returns (address instance) {
        bytes memory args = abi.encodePacked(address(this), vaultOwner);
        bytes32 salt = keccak256(args);
        (, instance) = LibClone.createDeterministicClone(_vaultImplementation, args, salt);
    }

    /// @dev Allows the `vaultOwner` to withdraw ERC20 tokens.
    function withdrawERC20OnVault(address vaultOwner, address token, address to, uint256 amount) public {
        ClustersCommunityBaseVaultBeta(vaultOf(vaultOwner)).withdrawERC20(msg.sender, token, to, amount);
    }

    /// @dev Allows the owner to withdraw native currency.
    function withdrawNativeOnVault(address vaultOwner, address to, uint256 amount) public {
        ClustersCommunityBaseVaultBeta(vaultOf(vaultOwner)).withdrawNative(msg.sender, to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     WITHDRAW FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner to withdraw ERC20 tokens.
    function withdrawERC20(address token, address to, uint256 amount)
        public
        onlyOwnerOrRoles(abi.encode(ADMIN_ROLE, WITHDRAWER_ROLE))
    {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @dev Allows the owner to withdraw native currency.
    function withdrawNative(address to, uint256 amount)
        public
        onlyOwnerOrRoles(abi.encode(ADMIN_ROLE, WITHDRAWER_ROLE))
    {
        SafeTransferLib.safeTransferETH(to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allow admins to set roles too.
    function _authorizeSetRole(address, uint256, bool) internal override onlyOwnerOrRoles(abi.encode(ADMIN_ROLE)) {}

    /// @dev For UUPSUpgradeable.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwnerOrRoles(abi.encode(ADMIN_ROLE)) {}
}
