// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IFNFTBond {

    struct Bond {
        uint256 bondID;
        uint48 mint;
        bytes4 levelID;
        uint16 weight;
        uint256 earned;
        uint256 unweightedShares;
        uint256 weightedShares;
        uint256 rewardDebt;
        uint256 shareDebt;
    }

    struct BondLevel {
        bytes4 levelID;
        bool active;
        uint256 price;
        uint16 weight;
        uint64 sellableAmount;
        string name;
    }

    function bondManager() external view returns (address);

    function totalActiveBondLevels() external view returns (uint8);

    function _linkBondManager(address _bondManager) external;

    function _addBondLevelAtIndex(string memory _name, uint256 _price, uint16 _weight, uint32 _sellableAmount, uint16 _index) external returns (bytes4);

    function _changeBondLevel(bytes4 levelID, string memory _name, uint256 _price, uint16 _weight, uint32 _sellableAmount) external;

    function _deactivateBondLevel(bytes4 levelID) external;

    function _activateBondLevel(bytes4 levelID, uint16 _index) external;

    function mintBonds(address _account, bytes4 levelID, uint8 _amount, uint256 _price) external;

    function claim(address _account, uint256 _bondID, uint256 issuedRewards, uint256 issuedShares) external;

    function setBaseURI(string memory baseURI_ ) external;

    function getActiveBondLevels() external view returns (bytes4[] memory);

    function getBondLevel(bytes4 _levelID) external view returns (BondLevel memory);

    function getBond(uint256 _bondID) external view returns (Bond memory);

    function getBondsIDsOf(address _account) external view returns (uint256[] memory);

    function tokenURI(uint256 _bondID) external view returns (string memory);

}