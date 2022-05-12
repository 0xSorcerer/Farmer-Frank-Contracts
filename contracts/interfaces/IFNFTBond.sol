// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IFNFTBond {

    struct Bond {
        uint256 bondID;
        bytes4 levelID;
        uint256 index;
    }

    function BondManager() external view returns (address);

    function getBond(uint256 bondID) external view returns (Bond memory);

    function getBondsIDsOf(address user) external view returns (uint256[] memory);

    function tokenURI(uint256 bondID) external view returns (string memory);

    function linkBondManager(address bondManager) external;

    function mintBonds(address user, bytes4 levelID, uint256 index, uint256 amount) external;

    function claim(address user, uint256 bondID, uint256 issuedRewards, uint256 issuedShares) external;

    function setBaseURI(string memory baseURI) external;

    function getBondShares(uint256 bondID) external view returns (uint256 unweightedShares, uint256 weightedShares);
}