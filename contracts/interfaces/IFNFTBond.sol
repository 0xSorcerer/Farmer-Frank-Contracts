// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IFNFTBond {

    struct Bond {
        uint256 bondID;
        bytes4 levelID;
        uint256 index;
        uint256 discount;
    }

    function approve(address to, uint256 tokenId) external;

    function balanceOf(address owner) external view returns (uint256);

    function baseURI() external view returns (string memory);

    function bondManager() external view returns (address);

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function name() external view returns (string memory);

    function owner() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function renounceOwnership() external;

    function setApprovalForAll(address operator, bool approved) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function tokenByIndex(uint256 index) external view returns (uint256);

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function getBond(uint256 bondID) external view returns (Bond memory bond);

    function getBondsIDsOf(address user) external view returns (uint256[] memory);

    function tokenURI(uint256 bondID) external view returns (string memory);

    function setBondManager(address manager) external;

    function mintBonds(address user, bytes4 levelID, uint256 index, uint256 amount, uint256 discount ) external;
    
    function setBondIndex(uint256 bondID, uint256 index) external;

    function setBaseURI(string memory baseURI) external;

    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) external;

    function transferFrom(address from, address to, uint256 tokenId) external;
}