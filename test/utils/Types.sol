// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Users {
    // Signer's private key
    uint256 signerPrivKey;
    // Frontend's signer
    address payable signer;
    // Default admin for Endpoint.sol
    address payable endpointAdmin;
    // Alice's primary address
    address payable alicePrimary;
    // Alice's secondary address
    address payable aliceSecondary;
    // Bob's primary address
    address payable bobPrimary;
    // Bob's secondary address
    address payable bobSecondary;
    // Bidder
    address payable bidder;
    // Malicious user
    address payable hacker;
}
