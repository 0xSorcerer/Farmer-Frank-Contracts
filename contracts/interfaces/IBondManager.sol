// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IBondManager {

    function baseToken() external view returns (address);

    function bond() external view returns (address);

    function treasury() external view returns (address);

    function accRewardsPerWS() external view returns (uint256);

    function accSharesPerUS() external view returns (uint256);

    function isDiscountActive() external view returns (bool);

    function isDiscountPlanned() external view returns (bool);

    function isSaleActive() external view returns (bool);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function totalUnweightedShares() external view returns (uint256);

    function totalWeightedShares() external view returns (uint256);

    function startDiscountAt(uint256 _startAt, uint256 _endAt, uint16 _discountRate, uint64 _updateFrequency, uint8[] memory _purchaseLimit) external;

    function startDiscountIn(uint256 _startIn, uint256 _endIn, uint16 _discountRate, uint64 _updateFrequency, uint8[] memory _purchaseLimit) external;

    function deactivateDiscount() external;

    function addBondLevel (string memory _name, uint16 _basePrice, uint16 _weight) external returns (bytes4);

    function addBondLevelAtIndex (string memory _name, uint16 _basePrice, uint16 _weight, uint16 _index) external returns (bytes4);

    function changeBondLevel (bytes4 levelID, string memory _name, uint16 _basePrice, uint16 _weight) external;

    function deactivateBondLevel (bytes4 levelID) external;

    function activateBondLevel (bytes4 levelID, uint16 _index) external;

    function rearrangeBondLevel (bytes4 levelID, uint16 _index) external;

    function setBaseURI (string memory baseURI_) external;

    function toggleSale () external;

    function createMultipleBondsWithTokens (bytes4 levelID, uint16 _amount) external;

    function depositRewards (uint256 _issuedRewards, uint256 _issuedShares) external;

    function claim (uint256 _bondID) external;

    function claimAll () external;

    function batchClaim (uint256[] memory _bondIDs) external;

    function getPrice (bytes4 levelID) external view returns (uint256, bool);

    function getClaimableAmounts (uint256 _bondID) external view returns (uint256 claimableShares, uint256 claimableRewards);

}