// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "clusters/ClustersNFTBaseURIRenderer.sol";

contract MockClustersNFTBaseURIRenderer is ClustersNFTBaseURIRenderer {
    function setOwner(address newOwner) public {
        _setOwner(newOwner);
    }
}
