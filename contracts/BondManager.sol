// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IFNFTBond.sol";

import "./other/Ownable.sol";

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IFrankTreasury.sol";
import "./interfaces/IERC721.sol";
import "./other/MerkleProof.sol";

/// @title Contract that deals with the discounting of fNFT Bonds.
/// @author @0xSorcerer

contract BondDiscountable {
    /// @notice Info of each Discount.
    struct Discount {
        // Timestamp at which the discount will start.
        uint256 startTime;
        // Timestamp at which whitelist will no longer be required to purchase bond (if 0 whitelist won't be required).
        uint256 endWhitelistTime;
        // Timestamp at which the discount will end.
        uint256 endTime;
        // Root of whitelisted addresses merkle tree.
        bytes32 merkleRoot;
        // Discount rate (percentage) (out of 1e18).
        uint256 discountRate;
        // Amount in seconds of how often discount price should update.
        uint256 updateFrequency;
        // Mapping of how many bonds per level can be minted every price update.
        mapping(bytes4 => uint256) purchaseLimit;
    }

    ///@dev Discount index. Used to distinguish between different discounts.
    uint256 internal discountIndex = 0;

    /// @dev Keep track of how many bonds have been sold during a discount.
    /// @dev discountedBondsSold[discountIndex][updateFactor][levelID]
    mapping(uint256 => mapping(uint256 => mapping(bytes4 => uint256)))
        internal discountedBondsSold;

    /// @dev Discounts mapping.
    /// @dev discount[discountIndex]
    mapping(uint256 => Discount) internal discount;

    /// @notice Returns the discount updateFactor.
    /// @return updateFactor The nth discount price update.
    function getDiscountUpdateFactor() public view returns (uint256 updateFactor) {
        updateFactor = (block.timestamp - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
    }

    /// @notice Returns whether a discount is planned for the future.
    function isDiscountPlanned() public view returns (bool) {
        return !(discount[discountIndex].startTime == 0);
    }

    /// @notice Returns whether a discount is currently active.
    function isDiscountActive() public view returns (bool) {
        if (isDiscountPlanned()) {
            uint256 cTime = block.timestamp;
            if (discount[discountIndex].startTime < cTime && discount[discountIndex].endTime > cTime) {
                return true;
            }
        }

        return false;
    }

    /// @notice Returns whether a discount requires whitelist to participate.
    function isDiscountWhitelisted() public view returns (bool whitelisted) {
        require(isDiscountPlanned());
        discount[discountIndex].endWhitelistTime == 0 ? whitelisted = false : whitelisted = true;
    }

    /// @notice Create a non whitelisted discount.
    /// @param _startTime Timestamp at which discount will start.
    /// @param _endTime Timestamp at which discount will end.
    /// @param _discountRate Discount percentage (out of 100).
    /// @param _updateFrequency Amount in seconds of how often discount price should update.
    /// @param _purchaseLimit Mapping of how many bonds per level can be minted every price update.
    /// @param _levelIDs Bond level hex IDs for all active bond levels.
    function _startDiscount(uint256 _startTime, uint256 _endTime, uint256 _discountRate, uint256 _updateFrequency, uint256[] memory _purchaseLimit, bytes4[] memory _levelIDs) internal {
        uint256 cTime = block.timestamp;
        require(_startTime >= cTime, "Bond Discountable: Start timestamp must be > than current timestamp.");
        require(_endTime > _startTime, "Bond Discountable: End timestamp must be > than current timestamp.");
        require(_updateFrequency < (_endTime - _startTime), "Bond Discountable: Update frequency must be < than discount duration.");
        require((_endTime - _startTime) % _updateFrequency == 0, "Bond Discountable: Discount duration must be divisible by the update frequency.");
        require(_discountRate <= 1e18 && _discountRate > 0, "Bond Discountable: Discount rate must be a percentage.");
        require(!isDiscountPlanned(), "Bond Discountable: There is already a planned discount.");
        require(_levelIDs.length == _purchaseLimit.length, "Bond Discountable: Invalid amount of param array elements.");

        discount[discountIndex].startTime = _startTime;
        discount[discountIndex].endTime = _endTime;
        discount[discountIndex].discountRate = _discountRate;
        discount[discountIndex].updateFrequency = _updateFrequency;

        for (uint256 i = 0; i < _levelIDs.length; i++) {
            discount[discountIndex].purchaseLimit[_levelIDs[i]] = _purchaseLimit[i];
        }
    }

    /// @notice Create a non whitelisted discount.
    /// @param _startTime Timestamp at which discount will start.
    /// @param _endWhitelistTime Timestamp at which whitelist will no longer be required to purchase bond (if 0 whitelist won't be required).
    /// @param _endTime Timestamp at which discount will end.
    /// @param _merkleRoot Root of whitelisted addresses merkle tree.
    /// @param _discountRate Discount percentage (out of 100).
    /// @param _updateFrequency Amount in seconds of how often discount price should update.
    /// @param _purchaseLimit Mapping of how many bonds per level can be minted every price update.
    /// @param _levelIDs Bond level hex IDs for all active bond levels.
    function _startWhitelistedDiscount(uint256 _startTime, uint256 _endWhitelistTime, uint256 _endTime, bytes32 _merkleRoot, uint256 _discountRate, uint256 _updateFrequency, uint256[] memory _purchaseLimit, bytes4[] memory _levelIDs) internal {
        require(_endWhitelistTime > _startTime);
        require(_endWhitelistTime <= _endTime);
        require((_endWhitelistTime - _startTime) % _updateFrequency == 0);

        _startDiscount(_startTime, _endTime, _discountRate, _updateFrequency, _purchaseLimit, _levelIDs);

        discount[discountIndex].endWhitelistTime = _endWhitelistTime;
        discount[discountIndex].merkleRoot = _merkleRoot;
    }

    /// @notice Cancels current discount.
    function _deactivateDiscount() internal {
        discountIndex++;
    }
}

/// @title Middleman between a user and fNFT bond contract.
/// @author @0xSorcerer

/// Users will use this contract to mint bonds and claim their rewards.

/// UNWEIGHTED SHARES -> Used to distribute share rewards issued to bonds.
///     At mint (no discount), unweighted shares metrics is the bond's ORIGINAL price.
///     At mint (discount), unweighted shares metrics is the bond's DISCOUNTED price.
///
/// WEIGHTED SHARES -> Used to distribute token rewards issued to bonds.
///     At mint (with and without discount), weighted shares metrics is the bond's ORIGINAL price multiplied by the bond's weight.

/// When revenue gets redistributed within FrankTreasury, a part is reinvested, and a part is rewarded as tokens to bond holders.
///     The reinvested amount is accounted for in the form of share issuance to all bonds. These issued shares are divided between bonds
///     according to their amount of unweightedShares compared to the total amount of unweightedShares. 
///
///     The tokens rewards are divided between bonds according to their amount of weightedShares compared to the total amount of weightedShares.

/// Upon claiming, the shares received by a bond will increase both its weighted shares and unweighted shares.
///     Unweighted shares will simply increase by the amount of shares received.
///     Weighted shares will increase by the amount of shares received multiplied by the bond's weight. 

contract BondManager is Ownable, BondDiscountable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Info of each user.
    struct User {
        // Total number of unweighted shares a user owns.
        uint256 unweightedShares;
        // Total number of weighted shares a user owns.
        uint256 weightedShares;
        // User's shares debt.
        uint256 shareDebt;
        // User's token debt.
        uint256 rewardDebt;
        // User's experience points.
        uint256 XP;
        // User's index.
        // Used to keep track of compounding and to calculate an individual bond's amount of shares.
        uint256 index;
    }

    /// @notice Info of each Bond level. 
    struct BondLevel {
        // Unique fNFT Bond level hex ID.
        bytes4 levelID;
        // Whether bonds of this level can be currently minted.
        bool active;
        // Bond level name used on Farmer Frank's UI.
        string name;
        // Maximum supply of bonds of that level. If set to 0, the maximum supply is unlimited.
        uint256 weight;
        // Bond level name used on Farmer Frank's UI.
        uint256 maxSupply;
        // Bond price.
        uint256 price;
    }

    /// @notice fNFT Bond interface.
    IFNFTBond public bond;

    /// @notice Token used to mint Bonds and issue rewards.
    IERC20 public baseToken;

    /// @notice Farmer Frank Treasury interface. 
    IFrankTreasury public treasury;

    /// @dev Precision constant.
    uint256 private constant PRECISION = 1e18;

    /// @notice Total number of unweighted shares.
    uint256 public totalUnweightedShares;
    /// @notice Total number of weighted shares.
    uint256 public totalWeightedShares;

    /// @notice Accumulated rewards per weigted shares. Used to calculate claim amount & rewardDebt.
    uint256 public accRewardsPerWS = 0;
    /// @notice Accumulated shares per unweighted shares. Used to calculate claim amount & shareDebt.
    uint256 public accSharesPerUS = 0;

    /// @notice Whether bond sale is currently active.
    bool public isSaleActive = true;

    /// @dev Mapping storing all user's data.
    mapping(address => User) private users;

    /// @dev Maximum amount of Bond levels that can be concurrently active.
    uint256 private constant MAX_BOND_LEVELS = 10;

    /// @dev Array storing all active Bond levels.
    bytes4[] private activeBondLevels;

    /// @dev Mapping storing all Bond levels, both active and inactive.
    /// @dev Inactive bondLevels must be stored in order to retreive data such as weight for bonds of that level,
    /// even if it isn't currently active.
    mapping(bytes4 => BondLevel) private bondLevels;

    /// @dev Mapping storing how many bonds have been minted per level.
    /// @dev Used to ensure a bond's level maximum supply is not being exceeded.
    /// @dev Used only for bond levels which have a fixed supply. 
    mapping(bytes4 => uint256) private bondsSold;

    event DISCOUNT_CREATE(uint256 indexed discountIndex, uint256 startTime, uint256 endTime, uint256 discountRate, bool whitelist);
    event BOND_LEVEL_CREATE(bytes4 indexed levelID, string name, uint256 weight, uint256 maxSupply, uint256 price);
    event BOND_LEVEL_CHANGE(bytes4 indexed levelID, string name, uint256 weight, uint256 maxSupply, uint256 price);
    event BOND_LEVEL_TOGGLE(bytes4 indexed levelID, bool activated);
    event BONDS_CREATE(address indexed user, bytes4 indexed levelID, uint256 amount);
    event SALE_TOGGLE(bool activated);
    event REWARDS_DEPOSIT(uint256 issuedRewards, uint256 issuedShares);

    constructor(address _bond, address _baseToken, address _treasury) {
        require(_bond != address(0));
        require(_baseToken != address(0));
        require(_treasury != address(0));

        bond = IFNFTBond(_bond);
        baseToken = IERC20(_baseToken);

        setTreasury(_treasury);

        addBondLevelAtIndex("Level I", (100 * 10**16), 0, activeBondLevels.length, (10 * PRECISION), true);
        addBondLevelAtIndex("Level II", (105 * 10**16), 0, activeBondLevels.length, (100 * PRECISION), true);
        addBondLevelAtIndex("Level III", (110 * 10**16), 0, activeBondLevels.length, (1000 * PRECISION), true);
        addBondLevelAtIndex("Level IV", (115 * 10**16), 0, activeBondLevels.length, (5000 * PRECISION), true);
    }

    /// @notice Get user object.
    /// @param user User's address.
    function getUser(address user) public view returns (User memory) {
        return users[user];
    }

    /// @notice Get amount of shares for bond at bondID.
    /// @param bondID Unique fNFT Bond ID.
    /// @return unweightedShares Amount of unweighted shares.
    /// @return weightedShares Amount of weighted shares.
    /// @return growthMultiplier Share increase multiplier since mint. 
    function getBondShares(uint256 bondID) public view returns (uint256 unweightedShares, uint256 weightedShares, uint256 growthMultiplier) {
        address bondOwner = IERC721(address(bond)).ownerOf(bondID);

        IFNFTBond.Bond memory _bond = bond.getBond(bondID);

        growthMultiplier = (users[bondOwner].index * PRECISION) / _bond.index;

        uint256 baseShares = ((growthMultiplier * getBondLevel(_bond.levelID).price) / PRECISION);

        unweightedShares = (baseShares * _bond.discount) / PRECISION;
        weightedShares = (baseShares * getBondLevel(_bond.levelID).weight) / PRECISION;
    }

    /// @notice Returns an array of all hex IDs of active Bond levels.
    function getActiveBondLevels() public view returns (bytes4[] memory) {
        return activeBondLevels;
    }

    /// @notice Returns Bond level.
    /// @param levelID Unique fNFT Bond level hex ID.
    function getBondLevel(bytes4 levelID) public view returns (BondLevel memory) {
        return bondLevels[levelID];
    }

    /// @notice Get the price for a particular Bond level.
    /// @param levelID Bond level hex ID.
    /// @return uint256 Bond price.
    /// @return bool Whether a discont is currently active.
    function getBondPrice(bytes4 levelID) public view returns (uint256, bool) {
        uint256 price = getBondLevel(levelID).price;

        if (isDiscountActive()) {
            // Calculates total number of price updates during the discount time frame.
            uint256 totalUpdates = (discount[discountIndex].endTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
            // Calculates the price when discount starts: the lowest price. Simply, the base price discounted by the discount rate.
            uint256 discountStartPrice = price - ((price * discount[discountIndex].discountRate) / PRECISION);
            // Calculates how much price will increase at every price update.
            uint256 updateIncrement = (price - discountStartPrice) / totalUpdates;
            // Finally calcualtes the price using the above variables.
            return (discountStartPrice + (updateIncrement * getDiscountUpdateFactor()), true);
        } else {
            return (price, false);
        }
    }

    /// @notice Get user's claimable amount of shares and rewards.
    /// @param user User's address.
    /// @return claimableShares Claimable amount of shares.
    /// @return claimableRewards Claimable amount of rewards.
    function getClaimableAmounts(address user) public view returns (uint256 claimableShares, uint256 claimableRewards) {
        claimableShares = ((users[user].unweightedShares * accSharesPerUS) / PRECISION) - users[user].shareDebt;
        claimableRewards = ((users[user].weightedShares * accRewardsPerWS) / PRECISION) - users[user].rewardDebt;
    }

    /// @notice Links this bond manager to the fNFT bond at deployment.
    function linkBondManager() external onlyOwner {
        bond.setBondManager(address(this));
    }

    /// @notice external onlyOnwer implementation of setBaseURI (fNFT Bond function)
    /// @param baseURI string to set as baseURI
    function setBaseURI(string memory baseURI) external onlyOwner {
        return bond.setBaseURI(baseURI);
    }

    /// @notice Starts normal discount (without whitelist) at specific timestamp.
    /// @dev See BondDiscountable.
    function startDiscountAt(uint256 startAt, uint256 endAt, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startDiscount(startAt, endAt, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        
        emit DISCOUNT_CREATE(discountIndex, startAt, endAt, discountRate, false);
    }

    /// @notice Starts normal discount (without whitelist) in specific amount of time.
    /// @dev See BondDiscountable.
    function startDiscountIn(uint256 startIn, uint256 endIn, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;
        _startDiscount(cTime + startIn, cTime + endIn, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());

        emit DISCOUNT_CREATE(discountIndex, cTime + startIn, cTime + endIn, discountRate, false);
    }

    /// @notice Starts whitelisted discount at specific timestamp.
    /// @dev See BondDiscountable.
    function startWhitelistedDiscountAt(uint256 startAt, uint256 endWhitelistAt, uint256 endAt, bytes32 merkleRoot, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startWhitelistedDiscount(startAt, endWhitelistAt, endAt, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());

        emit DISCOUNT_CREATE(discountIndex, startAt, endAt, discountRate, true);
    }

    /// @notice Starts whitelisted discount in specific amount of time.
    /// @dev See BondDiscountable.
    function startWhitelistedDiscountIn(uint256 startIn, uint256 endWhitelistIn, uint256 endIn, bytes32 merkleRoot, uint256 discountRate, uint256 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;
        _startWhitelistedDiscount(cTime + startIn, cTime + endWhitelistIn, cTime + endIn, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());

        emit DISCOUNT_CREATE(discountIndex, cTime + startIn, cTime + endIn, discountRate, true);
    }

    /// @notice Deactivates a discount.
    function deactivateDiscount() external onlyOwner {
        _deactivateDiscount();
    }

    /// @notice Set the treasury contract interface.
    /// @param _treasury FrankTreasury contract address.
    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0));
        treasury = IFrankTreasury(_treasury);
    }

    /// @notice Create a Bond level and adds it at a particular index of activeBondLevels array.
    /// @param name Bond level name. Showed on Farmer Frank's UI.
    /// @param weight Weight percentage of Bond level with 1e18 precision.
    /// @param maxSupply Maximum supply of bonds of that level. If set to 0, there isn't a maximum supply.
    /// @param index Index of activeBondLevels array where the Bond level will be inserted.
    /// @param price Bond price.
    /// @param active Whether the bond level starts as active.
    /// @dev Index and order of activeBondLevels array is crucial as it dictates hierarchy of display
    /// on Farmer Frank's UI.
    /// @dev If the Bond level must be added at the end of the array --> _index = activeBondLevels.length.
    /// @dev When adding a bond level whose index isn't activeBondLevels.length, the contract loops through
    /// the array shifting its elements. We disregard unbounded gas cost possible error as the contract
    /// is designed to store a "concise" amount of Bond levels: 10 --> MAX_BOND_LEVELS.
    function addBondLevelAtIndex(string memory name, uint256 weight, uint256 maxSupply, uint256 index, uint256 price, bool active) public onlyOwner returns (bytes4) {
        require(!isDiscountPlanned(), "Bond Manager: Can't add bond level during a discount.");
        require(MAX_BOND_LEVELS > activeBondLevels.length, "Bond Manager: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(index <= activeBondLevels.length,"Bond Manager: Index out of bounds.");

        bytes4 levelID = bytes4(keccak256(abi.encodePacked(name, weight, block.timestamp, price)));

        BondLevel memory bondLevel = BondLevel({
            levelID: levelID,
            active: active,
            name: name,
            weight: weight,
            maxSupply: maxSupply,
            price: price
        });

        if(active) {
            activeBondLevels.push();

            for (uint256 i = activeBondLevels.length - 1; i >= index; i--) {
                if (i == index) {
                    activeBondLevels[i] = levelID;
                    break;
                } else {
                    activeBondLevels[i] = activeBondLevels[i - 1];
                }
            }
        }

        bondLevels[levelID] = bondLevel;

        emit BOND_LEVEL_CREATE(levelID, name, weight, maxSupply, price);

        return (levelID);
    }

    /// @notice Create a Bond level and adds it at the end of activeBondLevels array.
    /// @dev For params see addBondLevelAtIndex()
    function addBondLevel(string memory name, uint256 weight, uint256 maxSupply, uint256 price, bool active) external onlyOwner returns (bytes4) {
        return addBondLevelAtIndex(name, weight, maxSupply, activeBondLevels.length, price, active);
    }

    /// @notice Changes a Bond level.
    /// @param levelID Unique fNFT Bond level hex ID.
    /// @dev For params see addBondLevelAtIndex()
    function changeBondLevel(bytes4 levelID, string memory name, uint256 weight, uint256 maxSupply, uint256 price) external onlyOwner {
        bondLevels[levelID] = BondLevel({
            levelID: levelID,
            active: true,
            name: name,
            weight: weight,
            maxSupply: maxSupply,
            price: price
        });

        emit BOND_LEVEL_CHANGE(levelID, name, weight, maxSupply, price);
    }

    /// @notice Deactivates a Bond level.
    /// @param levelID Unique fNFT Bond level hex ID.
    function deactivateBondLevel(bytes4 levelID) public onlyOwner {
        require(bondLevels[levelID].active == true, "Bond Manager: Level is already inactive.");

        uint256 index;
        bool found = false;

        for (uint256 i = 0; i < activeBondLevels.length; i++) {
            if (activeBondLevels[i] == levelID) {
                index = i;
                found = true;
                break;
            }
        }

        if (!found) {
            revert();
        }

        for (uint256 i = index; i < activeBondLevels.length - 1; i++) {
            activeBondLevels[i] = activeBondLevels[i + 1];
        }

        activeBondLevels.pop();
        bondLevels[levelID].active = false;

        emit BOND_LEVEL_TOGGLE(levelID, false);
    }

    /// @notice Activate a Bond level.
    /// @param levelID Unique fNFT Bond level hex ID.
    /// @param index activeBondLevels array's index where level should be placed.
    function activateBondLevel(bytes4 levelID, uint256 index) public onlyOwner {
        require(!(activeBondLevels.length >= MAX_BOND_LEVELS), "Bond Manager: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(index <= activeBondLevels.length, "Bond Manager: Index out of bounds.");
        require(bondLevels[levelID].active == false, "Bond Manager: Level is already active.");

        activeBondLevels.push();

        for (uint256 i = activeBondLevels.length - 1; i >= index; i--) {
            if (i == index) {
                activeBondLevels[i] = levelID;
                break;
            } else {
                activeBondLevels[i] = activeBondLevels[i - 1];
            }
        }

        bondLevels[levelID].active = true;

        emit BOND_LEVEL_TOGGLE(levelID, true);
    }

    /// @notice Changes Bond level index in activeBondLevels array.
    /// @param levelID Unique fNFT Bond level hex ID.
    /// @param index activeBondLevels array's index where level should be placed.
    function rearrangeBondLevel(bytes4 levelID, uint256 index) external onlyOwner {
        deactivateBondLevel(levelID);
        activateBondLevel(levelID, index);
    }

    /// @notice Toggle fNFT Bond sale.
    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;

        emit SALE_TOGGLE(isSaleActive);
    }

    /// @notice Sets a user's data.
    /// @param user User's address.
    /// @param unweightedShares New amount of user's unweighted shares.
    /// @param weightedShares New amount of user's weighted shares.
    /// @param XP New user's XP amount.
    function setUserData(address user, uint256 unweightedShares, uint256 weightedShares, uint256 XP) internal {
        users[user].unweightedShares = unweightedShares;
        users[user].weightedShares = weightedShares;

        uint256 shareDebt;
        uint256 rewardDebt;

        if(unweightedShares == 0) {
            shareDebt = 0;
            rewardDebt = 0;
        } else {
            shareDebt = (unweightedShares * accSharesPerUS) / PRECISION;
            rewardDebt = (weightedShares * accRewardsPerWS) / PRECISION;
        }

        users[user].shareDebt = shareDebt;
        users[user].rewardDebt = rewardDebt;

        users[user].XP = XP;
    }

    /// @notice Function the user calls to mint (create) 1 or more fNFT Bonds.
    /// @param levelID Unique fNFT Bond level hex ID.
    /// @param amount Desired amount to be minted.
    /// @param merkleProof merkle proof needed only when a whitelisted discount is active. 
    function createMultipleBondsWithTokens(bytes4 levelID, uint256 amount, bytes32[] calldata merkleProof) public {
        require(isSaleActive, "Bond Manager: Bond sale is inactive.");
        require(amount > 0 && amount <= 20, "Bond Manager: Invalid amount to mint.");
        require(getBondLevel(levelID).active, "Bond Manager: Bond level is inactive.");

        address user = _msgSender();

        uint256 lPrice = bondLevels[levelID].price;
        uint256 lMaxSupply = bondLevels[levelID].maxSupply;

        if (lMaxSupply != 0) {
            require(lMaxSupply >= bondsSold[levelID] + amount, "Bond Manager: Exceeding Bond level maximum supply.");
            bondsSold[levelID] += amount;
        }

        claim(user);

        (uint256 bondPrice, bool discountActive) = getBondPrice(levelID);

        uint256 _discount = PRECISION;

        if (discountActive) {
            if (discount[discountIndex].endWhitelistTime != 0 && discount[discountIndex].endWhitelistTime > block.timestamp) {
                bytes32 leaf = keccak256(abi.encodePacked(user));
                require(MerkleProof.verify(merkleProof, discount[discountIndex].merkleRoot, leaf), "Bond Manager: You are not whitelisted.");
            }

            uint256 updateFactor = getDiscountUpdateFactor();
            uint256 _bondsSold = uint16(SafeMath.add(discountedBondsSold[discountIndex][updateFactor][levelID], amount));
            require(_bondsSold <= discount[discountIndex].purchaseLimit[levelID], "Bond Manager: Too many bonds minted during this price update period.");

            discountedBondsSold[discountIndex][updateFactor][levelID] = _bondsSold;

            _discount = (bondPrice * PRECISION) / lPrice;
        }

        require(baseToken.balanceOf(user) >= bondPrice * amount, "Bond Manager: Your balance can't cover the mint cost.");
        treasury.bondDeposit(bondPrice * amount, user);

        uint256 unweightedShares = bondPrice * amount;
        uint256 weightedShares = (lPrice * amount * bondLevels[levelID].weight) / PRECISION;

        totalUnweightedShares += unweightedShares;
        totalWeightedShares += weightedShares;

        setUserData(user, (users[user].unweightedShares + unweightedShares), (users[user].weightedShares + weightedShares), (users[user].XP + lPrice));

        bond.mintBonds(user, levelID, users[user].index, amount, _discount);

        emit BONDS_CREATE(user, levelID, amount);
    }

    /// @notice onlyOwner function used to mint bonds without sending JOE.
    /// @param levelID Unique fNFT Bond level hex ID.
    /// @param amount Desired amount to be minted.
    /// @dev Used to mint limited edition bonds to auction, enabling JOE to be added later on.
    function createMultipleBonds(bytes4 levelID, uint256 amount) external onlyOwner {
        if (bondLevels[levelID].maxSupply != 0) {
            require(bondLevels[levelID].maxSupply >= bondsSold[levelID] + amount, "Bond Manager: Exceeding Bond level maximum supply.");
            bondsSold[levelID] += amount;
        }

        address user = _msgSender();

        claim(user);

        uint256 price = bondLevels[levelID].price;

        uint256 unweightedShares = price * amount;
        uint256 weightedShares = (price * amount * bondLevels[levelID].weight) / PRECISION;

        totalUnweightedShares += unweightedShares;
        totalWeightedShares += weightedShares;

        setUserData(user, (users[user].unweightedShares + unweightedShares), (users[user].weightedShares + weightedShares), (users[user].XP + price));

        bond.mintBonds(user, levelID, users[user].index, amount, PRECISION);

        emit BONDS_CREATE(user, levelID, amount);
    }

    /// @notice Deposit rewards and shares for users to be claimed from this contract.
    /// @param issuedRewards Amount of rewards to be deposited to the contract claimable by users.
    /// @param issuedShares Amount of new shares claimable by users.
    /// @dev Can only be called by treasury.
    function depositRewards(uint256 issuedShares, uint256 issuedRewards) external {
        require(_msgSender() == address(treasury));

        baseToken.transferFrom(address(treasury), address(this), issuedRewards);

        accSharesPerUS += (issuedShares * PRECISION) / totalUnweightedShares;
        accRewardsPerWS += (issuedRewards * PRECISION) / totalWeightedShares;

        emit REWARDS_DEPOSIT(issuedRewards, issuedShares);
    }

    /// @notice Function called by bond contract upon transfer of fNFT Bonds.
    /// @param from Address of user sending his bond.
    /// @param to Address receiving bond.
    /// @param bondID ID of the bond being sold.
    /// @dev As the Bond struct declared in fNFT bond no longer stores shares data, this
    /// function must be called to perform calculations to transfer shares data to the
    /// new holder.
    function dataTransfer(address from, address to, uint256 bondID) external {
        require(_msgSender() == address(bond));

        claim(from);
        claim(to);

        (uint256 unweightedShares, uint256 weightedShares, uint256 previousMultiplier) = getBondShares(bondID);

        uint256 newIndex = (users[to].index * PRECISION) / previousMultiplier;

        uint256 XP = getBondLevel(bond.getBond(bondID).levelID).price;

        if (IERC721(address(bond)).balanceOf(from) == 1) {
            setUserData(from, 0, 0, 0);
            users[from].index = 1e18;
        } else {
            setUserData(from, (users[from].unweightedShares - unweightedShares), (users[from].weightedShares - weightedShares), (users[from].XP - XP));
        }
        
        setUserData(to, (users[to].unweightedShares + unweightedShares), (users[to].weightedShares + weightedShares), (users[to].XP + XP));

        bond.setBondIndex(bondID, newIndex);
    }

    /// @notice Function called by user to claim rewards and shares.
    /// @param user User's address.
    function claim(address user) public {
        (uint256 claimableShares, uint256 claimableRewards) = getClaimableAmounts(user);

        if (users[user].index == 0) {
            users[user].index = 1e18;
        }

        if (claimableShares == 0 && claimableRewards == 0) {
            return;
        }

        uint256 _unweightedShares = users[user].unweightedShares;
        uint256 _weightedShares = users[user].weightedShares;

        uint256 userWeight = ((_weightedShares * PRECISION) / _unweightedShares);
        uint256 claimableWeightedShares = ((claimableShares * userWeight) / PRECISION);

        users[user].index = (users[user].index * (((claimableShares * PRECISION) / _unweightedShares) + PRECISION)) / PRECISION;

        setUserData(user, (_unweightedShares + claimableShares), (_weightedShares + claimableWeightedShares), (users[user].XP));

        totalUnweightedShares += claimableShares;
        totalWeightedShares += claimableWeightedShares;

        baseToken.safeTransfer(user, claimableRewards);
    }

    /// @notice Open-ended execute function.
    function execute(address target, uint256 value, bytes calldata data) external onlyOwner returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        return (success, result);
    }

}