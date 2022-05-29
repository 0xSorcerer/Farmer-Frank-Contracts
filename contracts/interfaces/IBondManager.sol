// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IBondManager {

    struct BondLevel {
        bytes4 levelID;
        bool active;
        string name;
        uint256 weight;
        uint256 maxSupply;
        uint256 price;
    }

    struct User {
        uint256 unweightedShares;
        uint256 weightedShares;
        uint256 shareDebt;
        uint256 rewardDebt;
        uint256 XP;
        uint256 index;
    }

    function accRewardsPerWS() external view returns (uint256);

    function accSharesPerUS() external view returns (uint256);

    function baseToken() external view returns (address);

    function bond() external view returns (address);

    function getDiscountUpdateFactor() external view returns (uint256 updateFactor);

    function isDiscountActive() external view returns (bool);

    function isDiscountPlanned() external view returns (bool);

    function isDiscountWhitelisted() external view returns (bool whitelisted);

    function isSaleActive() external view returns (bool);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function totalUnweightedShares() external view returns (uint256);

    function totalWeightedShares() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function treasury() external view returns (address);

    function getUser(address user) external view returns (User memory);

    function getBondShares(uint256 bondID) external view returns (uint256 unweightedShares, uint256 weightedShares, uint256 growthMultiplier);

    function getActiveBondLevels() external view returns (bytes4[] memory);

    function getBondLevel(bytes4 levelID) external view returns (BondLevel memory);

    function getBondPrice(bytes4 levelID) external view returns (uint256, bool);

    function getClaimableAmounts(address user) external view returns (uint256 claimableShares, uint256 claimableRewards);

    function linkBondManager() external;

    function setBaseURI(string memory baseURI) external;

    function startDiscountAt(uint256 startAt, uint256 endAt, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external;

    function startDiscountIn(uint256 startIn, uint256 endIn, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external;

    function startWhitelistedDiscountAt(uint256 startAt, uint256 endWhitelistAt, uint256 endAt, bytes32 merkleRoot, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external;

    function startWhitelistedDiscountIn(uint256 startIn, uint256 endWhitelistIn, uint256 endIn, bytes32 merkleRoot, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external;

    function deactivateDiscount() external;

    function setTreasury(address _treasury) external;

    function addBondLevelAtIndex(string memory name, uint256 weight, uint256 maxSupply, uint256 index, uint256 price, bool active) external returns (bytes4);

    function addBondLevel(string memory name, uint256 weight, uint256 maxSupply, uint256 price, bool active) external returns (bytes4);

    function changeBondLevel(bytes4 levelID, string memory name, uint256 weight, uint256 maxSupply, uint256 price) external;

    function deactivateBondLevel(bytes4 levelID) external;

    function activateBondLevel(bytes4 levelID, uint256 index) external;

    function rearrangeBondLevel(bytes4 levelID, uint256 index) external;

    function toggleSale() external;

    function createMultipleBondsWithTokens(bytes4 levelID, uint256 amount, bytes32[] memory merkleProof) external;

    function createMultipleBonds(bytes4 levelID, uint256 amount) external;

    function depositRewards(uint256 issuedShares, uint256 issuedRewards) external;

    function dataTransfer(address from, address to, uint256 bondID) external;

    function claim(address user) external;

    function execute(address target, uint256 value, bytes calldata data) external returns (bool, bytes memory);
}   