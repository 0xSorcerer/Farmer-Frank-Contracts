// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IFNFTBond {

    struct Bond {
        uint256 bondID;
        uint48 mint;
        bytes4 levelID;
        uint256 earned;
        uint256 unweightedShares;
        uint256 weightedShares;
        uint256 rewardDebt;
        uint256 shareDebt;
    }

    function bondManager() external view returns (address);

    function _linkBondManager(address _bondManager) external;

    function mintBonds(address _account, bytes4 levelID, uint8 _amount, uint256 _weightedShares, uint256 _unweightedShares) external;

    function claim(address _account, uint256 _bondID, uint256 issuedRewards, uint256 issuedShares) external;

    function setBaseURI(string memory baseURI_ ) external;

    function getBond(uint256 _bondID) external view returns (Bond memory);

    function getBondsIDsOf(address _account) external view returns (uint256[] memory);

    function tokenURI(uint256 _bondID) external view returns (string memory);

}