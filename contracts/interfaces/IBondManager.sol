// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IBondManager {

    struct BondLevel {
        bytes4 levelID;
        bool active;
        uint256 weight;
        uint256 maxSupply;
        string name;
        uint256 price;
    }

    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function baseToken() external view returns (address);

    function bond() external view returns (address);

    function treasury() external view returns (address);

    function accRewardsPerWS() external view returns (uint256);

    function accSharesPerUS() external view returns (uint256);

    function getDiscountUpdateFactor() external view returns (uint256 updateFactor);

    function isDiscountActive() external view returns (bool);

    function isDiscountPlanned() external view returns (bool);

    function isDiscountWhitelisted() external view returns (bool whitelisted);

    function isSaleActive() external view returns (bool);

    function totalUnweightedShares() external view returns (uint256);

    function totalWeightedShares() external view returns (uint256);

    function getActiveBondLevels() external view returns (bytes4[] memory);

    function getBondLevel(bytes4 levelID) external view returns (BondLevel memory);

    function getUserXP(address user) external view returns (uint256);

    function getPrice(bytes4 levelID) external view returns (uint256, bool);

    function getClaimableAmounts(uint256 bondID) external view returns (uint256 claimableShares, uint256 claimableRewards);

    function setTreasury(address _treasury) external;

    function startDiscountAt(uint256 startAt, uint256 endAt, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external;

    function startDiscountIn(uint256 startIn, uint256 endIn, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external;

    function startWhitelistedDiscountAt(uint256 startAt, uint256 endWhitelistAt, uint256 endAt, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external;

    function startWhitelistedDiscountIn(uint256 startIn, uint256 endWhitelistIn, uint256 endIn, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external;

    function deactivateDiscount() external;

    function addBondLevelAtIndex(string memory name, uint256 weight, uint256 maxSupply, uint256 index, uint256 price) external returns (bytes4);

    function addBondLevel(string memory name, uint256 weight, uint256 maxSupply, uint256 price) external returns (bytes4);

    function changeBondLevel(bytes4 levelID, string memory name, uint256 weight, uint256 maxSupply, uint256 price) external;

    function deactivateBondLevel(bytes4 levelID) external;

    function activateBondLevel(bytes4 levelID, uint256 index) external;

    function rearrangeBondLevel(bytes4 levelID, uint256 index) external;

    function toggleSale() external;

    function createMultipleBondsWithTokens(bytes4 levelID, uint256 amount, bytes32[] calldata merkleProof) external;

    function depositRewards(uint256 issuedRewards, uint256 issuedShares) external;

    function claim(uint256 bondID) external;

    function claimAll() external;

    function batchClaim(uint256[] memory bondIDs) external;

    function linkBondManager() external;

    function setUserXP(uint256 amount, address user) external;

    function setBaseURI(string memory baseURI) external;
}