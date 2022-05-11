// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IFNFTBond.sol";

import "./other/Ownable.sol";

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IFrankTreasury.sol";
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
        // Discount rate (percentage) (out of 100).
        // Gas optimization uint16 + uint240 = 32 bytes. 
        uint16 discountRate;
        // Amount in seconds of how often discount price should update. 
        uint240 updateFrequency;
        // Mapping of how many bonds per level can be minted every price update.
        mapping(bytes4 => uint256) purchaseLimit;
    }

    ///@dev Discount index. Used to distinguish between different discounts.
    uint256 internal discountIndex = 0;
    
    /// @dev Keep track of how many bonds have been sold during a discount.
    /// @dev discountedBondsSold[discountIndex][updateFactor][levelID]
    mapping(uint256 => mapping(uint256 => mapping(bytes4 => uint256))) internal discountedBondsSold;

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
    function _startDiscount(
        uint256 _startTime,
        uint256 _endTime,
        uint16 _discountRate,
        uint240 _updateFrequency,
        uint256[] memory _purchaseLimit,
        bytes4[] memory _levelIDs
    ) internal {
        uint256 cTime = block.timestamp;
        require(_startTime >= cTime, "Bond Discountable: Start timestamp must be > than current timestamp.");
        require(_endTime > _startTime, "Bond Discountable: End timestamp must be > than current timestamp."); 
        require(_updateFrequency < (_endTime - _startTime), "Bond Discountable: Update frequency must be < than discount duration."); 
        require((_endTime - _startTime) % _updateFrequency == 0, "Bond Discountable: Discount duration must be divisible by the update frequency.");
        require(_discountRate <= 100 && _discountRate > 0, "Bond Discountable: Discount rate must be a percentage.");
        require(!isDiscountPlanned(), "Bond Discountable: There is already a planned discount.");
        require(_levelIDs.length == _purchaseLimit.length, "Bond Discountable: Invalid amount of param array elements.");

        discount[discountIndex].startTime = _startTime;
        discount[discountIndex].endTime = _endTime;
        discount[discountIndex].discountRate = _discountRate;
        discount[discountIndex].updateFrequency = _updateFrequency;

        for(uint i = 0; i < _levelIDs.length; i++) {
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
    function _startWhitelistedDiscount(
        uint256 _startTime,
        uint256 _endWhitelistTime,
        uint256 _endTime,
        bytes32 _merkleRoot,
        uint16 _discountRate,
        uint240 _updateFrequency,
        uint256[] memory _purchaseLimit,
        bytes4[] memory _levelIDs
    ) internal {
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

/// @title Middleman between a user and its fNFT bond.  
/// @author @0xSorcerer

/// Users will use this contract to mint bonds and claim their rewards.

contract BondManager is Ownable, BondDiscountable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Info of each Bond level. 
    struct BondLevel {
        // Unique fNFT Bond level hex ID.
        bytes4 levelID;
        // Whether bonds of this level can be currently minted.
        bool active;
        // Bond weight multipliers. Used to calculate weighted shares.
        // Weight is percentage (out of 100), hence weight = 100 would mean 1x (base multiplier).
        uint256 weight;
        // Maximum supply of bonds of that level. If set to 0, the maximum supply is unlimited.
        uint256 maxSupply;
        // Bond level name used on Farmer Frank's UI.
        string name;
        // Bond price.
        uint256 price;
    }

    /// @notice fNFT Bond interface.
    IFNFTBond public bond;

    /// @notice Token used to mint Bonds and issue rewards.
    IERC20 public baseToken;

    /// @notice Farmer Frank Treasury interface. 
    IFrankTreasury public treasury;

    /// @notice Total number of unweighted shares.
    uint256 public totalUnweightedShares;
    /// @notice Total number of weighted shares.
    uint256 public totalWeightedShares;

    /// @notice Accumulated rewards per weigted shares. Used to calculate claim amount & rewardDebt.
    uint256 public accRewardsPerWS = 0;
    /// @notice Accumulated shares per unweighted shares. Used to calculate claim amount & shareDebt.
    uint256 public accSharesPerUS = 0;

    /// @dev Precision constants.
    uint256 private GLOBAL_PRECISION = 10**18;
    uint256 private WEIGHT_PRECISION = 100;

    /// @notice Whether bond sale is currently active.
    bool public isSaleActive = true;

    /// @dev Maximum amount of Bond levels that can be concurrently active.
    uint256 private constant MAX_BOND_LEVELS = 10;

    /// @dev Array storing all active Bond levels.
    bytes4[] private activeBondLevels;

    /// @dev Mapping storing all Bond levels, both active and inactive.
    /// @dev Inactive bondLevels must be stored in order to retreive data such as weight for bonds of that level,
    /// even if it can't currently be minted. 
    mapping(bytes4 => BondLevel) private bondLevels;

    /// @dev Mapping storing how many bonds have been minted per level.
    /// @dev Used to ensure a bond's level maximum supply is not being exceeded.
    /// @dev Used only for bond levels which have a fixed supply. 
    mapping(bytes4 => uint256) private bondsSold;

    /// @dev User XP which will be utilized in a future update of the protocol.
    /// @dev Each bond confers its holder an amount of experience points. Upon bond transfer, its XP will be
    /// transfered to the new bond holder. 
    mapping(address => uint256) private userXP;

    event DISCOUNT_CREATED (uint256 indexed discountIndex, uint256 startTime, uint256 endTime, uint16 discountRate, bool whitelist);

    event BOND_LEVEL_CREATED (bytes4 indexed levelID, string name, uint256 weight, uint256 maxSupply, uint256 price);

    event BOND_LEVEL_CHANGED (bytes4 indexed levelID, string name, uint256 weight, uint256 maxSupply, uint256 price);

    event BOND_LEVEL_TOGGLED (bytes4 indexed levelID, bool activated);

    event SALE_TOGGLED (bool activated);

    event REWARDS_DEPOSIT (uint256 issuedRewards, uint256 issuedShares);

    event Set (
        bool isSaleActive
    );

    event Update (
        uint256 issuedRewards,
        uint256 issuedShares
    );

    /// @param _bond fNFT Bond contract address.
    /// @param _baseToken Base Token contract address.
    /// @param _treasury Treasury address.
    constructor(address _bond, address _baseToken, address _treasury) {
        require(_bond != address(0));
        require(_baseToken != address(0));

        bond = IFNFTBond(_bond);
        baseToken = IERC20(_baseToken);
        setTreasury(_treasury);

        // Create initial bond levels. 
        addBondLevelAtIndex("Level I", 100, 0, activeBondLevels.length, SafeMath.mul(10, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level II", 105, 0, activeBondLevels.length, SafeMath.mul(100, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level III", 110, 0, activeBondLevels.length, SafeMath.mul(1000, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level IV", 115, 0, activeBondLevels.length, SafeMath.mul(5000, GLOBAL_PRECISION));
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

    /// @notice Returns a user's XP balance.
    function getUserXP(address user) external view returns (uint256) {
        return userXP[user];
    }

    /// @notice Get the price for a particular Bond level.
    /// @param levelID Bond level hex ID.
    /// @return uint256 Bond price.
    /// @return bool Whether a discont is currently active.
    function getPrice(bytes4 levelID) public view returns (uint256, bool) {
        uint256 price = getBondLevel(levelID).price;

        if(isDiscountActive()) {
            // Calculates total number of price updates during the discount time frame.
            uint256 totalUpdates = (discount[discountIndex].endTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
            // Calculates the price when discount starts: the lowest price. Simply, the base price discounted by the discount rate.
            uint256 discountStartPrice = price - ((price * discount[discountIndex].discountRate) / 100);
            // Calculates how much price will increase at every price update.
            uint256 updateIncrement = (price - discountStartPrice) / totalUpdates;
            // Finally calcualtes the price using the above variables.
            return (discountStartPrice + (updateIncrement * getDiscountUpdateFactor()), true);
        } else {
            return (price, false);
        }
    }

    /// @notice Get claimable amount of shares and rewards for a particular Bond.
    /// @param bondID Unique fNFT Bond uint ID
    /// @return claimableShares Amount of shares that can be claimed by the bond holder for _bondID. 
    /// @return claimableRewards Amount of token rewards that can be claimed by the bond holder for _bondID. 
    function getClaimableAmounts(uint256 bondID) public view returns (uint256 claimableShares, uint256 claimableRewards) {
        IFNFTBond.Bond memory _bond = bond.getBond(bondID);

        claimableShares = (_bond.unweightedShares * accSharesPerUS / GLOBAL_PRECISION) - _bond.shareDebt;
        claimableRewards = (_bond.weightedShares * accRewardsPerWS / GLOBAL_PRECISION) - _bond.rewardDebt;
    }

    /// @notice Set the treasury contract interface.
    /// @param _treasury FrankTreasury contract address.
    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0));
        treasury = IFrankTreasury(_treasury);
    }

    /// @notice external onlyOwner implementation of _startDiscount (BondDiscountable) function.
    /// @param startAt Timestamp at which the discount will start.
    /// @param endAt Timestamp at which the discount will end.
    /// @param discountRate Discount percentage (out of 100).
    /// @param updateFrequency Amount in seconds of how often discount price should update.
    /// @param purchaseLimit Array of how many bonds per level can be minted every price update.
    function startDiscountAt(uint256 startAt, uint256 endAt, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startDiscount(startAt, endAt, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, startAt, endAt, discountRate, false);
    }

    /// @notice external onlyOwner implementation of _startDiscount (BondDiscountable) function.
    /// @param startIn Amount of seconds until the discount start.
    /// @param endIn Amount of seconds until the discount end.
    /// @param discountRate Discount percentage (out of 100).
    /// @param updateFrequency Amount in seconds of how often discount price should update.
    /// @param purchaseLimit Array of how many bonds per level can be minted every price update.
    function startDiscountIn(uint256 startIn, uint256 endIn, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startDiscount(cTime + startIn, cTime + endIn, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, cTime + startIn, cTime + endIn, discountRate, false);
    }

    /// @notice external onlyOwner implementation of _startWhitelistedDiscount (BondDiscountable) function.
    /// @param startAt Timestamp at which the discount will start.
    /// @param endWhitelistAt Timestamp at which whitelist will no longer be required to participate in the discount.
    /// @param endAt Timestamp at which the discount will end.
    /// @param merkleRoot Root of Merkle Tree utilized to validate whitelist.
    /// @param discountRate Discount percentage (out of 100).
    /// @param updateFrequency Amount in seconds of how often discount price should update.
    /// @param purchaseLimit Array of how many bonds per level can be minted every price update.
    function startWhitelistedDiscountAt(uint256 startAt, uint256 endWhitelistAt, uint256 endAt, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startWhitelistedDiscount(startAt, endWhitelistAt, endAt, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, startAt, endAt, discountRate, true);
    }

    /// @notice external onlyOwner implementation of _startWhitelistedDiscount (BondDiscountable) function.
    /// @param startIn Amount of seconds until the discount start.
    /// @param endWhitelistIn Amount of seconds until whitelist will no longer be required to participate in the discount.
    /// @param endIn Amount of seconds until the discount end.
    /// @param merkleRoot Root of Merkle Tree utilized to validate whitelist.
    /// @param discountRate Discount percentage (out of 100).
    /// @param updateFrequency Amount in seconds of how often discount price should update.
    /// @param purchaseLimit Array of how many bonds per level can be minted every price update.
    function startWhitelistedDiscountIn(uint256 startIn, uint256 endWhitelistIn, uint256 endIn, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startWhitelistedDiscount(cTime + startIn, cTime + endWhitelistIn, cTime + endIn, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, cTime + startIn, cTime + endIn, discountRate, true);
    }

    /// @notice external onlyOwner implementation of _deactivateDiscount (BondDiscountable) function.
    function deactivateDiscount() external onlyOwner {
        _deactivateDiscount();
    }

    /// @notice Create a Bond level and adds it at a particular index of activeBondLevels array.
    /// @param name Bond level name. Showed on Farmer Frank's UI.
    /// @param weight Weight percentage of Bond level (>= 100).
    /// @param maxSupply Maximum supply of bonds of that level. If set to 0, there isn't a maximum supply.
    /// @param index Index of activeBondLevels array where the Bond level will be inserted.
    /// @param price Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
    /// @dev Index and order of activeBondLevels array is crucial as it dictates hierarchy of display
    /// on Farmer Frank's UI.
    /// @dev If the Bond level must be added at the end of the array --> _index = activeBondLevels.length.
    /// @dev When adding a bond level whose index isn't activeBondLevels.length, the contract loops through
    /// the array shifting its elements. We disregard unbounded gas cost possible error as the contract
    /// is designed to store a "concise" amount of Bond levels: 10 --> MAX_BOND_LEVELS.
    function addBondLevelAtIndex(string memory name, uint256 weight, uint256 maxSupply, uint256 index, uint256 price) public onlyOwner returns (bytes4) {
        require(!isDiscountPlanned(), "Bond Manager: Can't add bond level during a discount.");
        require(MAX_BOND_LEVELS > activeBondLevels.length, "Bond Manager: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(index <= activeBondLevels.length, "Bond Manager: Index out of bounds.");

        // Calculate unique Bond level hex ID.
        bytes4 levelID = bytes4(keccak256(abi.encodePacked(name, weight, block.timestamp, price)));

        BondLevel memory bondLevel = BondLevel({
            levelID: levelID,
            active: true,
            weight: weight,
            maxSupply: maxSupply,
            name: name,
            price: price
        });

        // Dealing with activeBondLevels elements shift to add Bond level at desired _index.

        activeBondLevels.push();

        for(uint i = activeBondLevels.length - 1; i >= index; i--) {
            if(i == index) {
                activeBondLevels[i] = levelID;
                break;
            } else {
                activeBondLevels[i] = activeBondLevels[i-1];
            }
        }
        
        bondLevels[levelID] = bondLevel;

        emit BOND_LEVEL_CREATED(levelID, name, weight, maxSupply, price);
        
        return(levelID);
    }

    /// @notice Create a Bond level and adds it at a particular index of activeBondLevels array.
    /// @param name Bond level name. Showed on Farmer Frank's UI.
    /// @param weight Weight percentage of Bond level (>= 100).
    /// @param maxSupply Maximum supply of bonds of that level. If set to 0, there isn't a maximum supply.
    /// @param price Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
    function addBondLevel(string memory name, uint256 weight, uint256 maxSupply, uint256 price) external onlyOwner returns (bytes4) {
        return addBondLevelAtIndex(name, weight, maxSupply, activeBondLevels.length, price);
    }

    /// @notice Change a Bond level.
    /// @param levelID Bond level hex ID being changed.
    /// @param name New Bond level name.
    /// @param weight New Weight percentage of Bond level (>= 100).
    /// @param maxSupply Maximum supply of bonds of that level. If set to 0, there isn't a maximum supply.
    /// @param price New Bond price.
    function changeBondLevel(bytes4 levelID, string memory name, uint256 weight, uint256 maxSupply, uint256 price) external onlyOwner {
        bondLevels[levelID] = BondLevel({
            levelID: levelID,
            active: true,
            weight: weight,
            maxSupply: maxSupply,
            name: name,
            price: price
        });

        emit BOND_LEVEL_CHANGED(levelID, name, weight, maxSupply, price);

    }

    /// @notice Deactivate a Bond level.
    /// @param levelID Bond level hex ID.
    /// @dev Bond being deactivated is removed from activeBondLevels array and its active parameter is set to false.
    /// @dev When removing a bond level, the contract loops through the activeBondLevels array shifting its elements.
    /// We disregard unbounded gas cost possible error as the contract is designed to store a "concise"
    /// amount of Bond levels: 10. 
    function deactivateBondLevel(bytes4 levelID) public onlyOwner {
        require(!isDiscountPlanned(), "Bond Manager: Can't deactivate bond level during a discount.");
        require(bondLevels[levelID].active == true, "Bond Manager: Level is already inactive.");

        // Dealing with activeBondLevels elements shift 
        uint index;
        bool found = false;

        for (uint i = 0; i < activeBondLevels.length; i++) {
            if(activeBondLevels[i] == levelID) {
                index = i;
                found = true;
                break;
            }
        }

        if(!found) {
            revert();
        }

        for(uint i = index; i < activeBondLevels.length - 1; i++) {
            activeBondLevels[i] = activeBondLevels[i + 1];
        }

        activeBondLevels.pop();
        bondLevels[levelID].active = false;

        emit BOND_LEVEL_TOGGLED(levelID, false);
    }

    /// @notice Activate a Bond level. Bond level activation & deactivation can serve to introduce interesting mechanics.
    /// For instance, Limited Edition levels can be introduced. They can be active for limited periods of time, enabling
    /// Farmer Frank's Team to manage their availability at will. 
    /// @param levelID Bond level hex ID.
    /// @param index Index of activeBondLevels array where the Bond level will be inserted.
    /// @dev When activating a bond level, the contract loops through the activeBondLevels array shifting its elements.
    /// We disregard unbounded gas cost possible error as the contract is designed to store a "concise"
    /// amount of Bond levels: 10.
    function activateBondLevel(bytes4 levelID, uint256 index) public onlyOwner {
        require(!isDiscountPlanned(), "Bond Manager: Can't activate bond level during a discount.");
        require(!(activeBondLevels.length >= MAX_BOND_LEVELS), "Bond Manager: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(index <= activeBondLevels.length, "Bond Manager: Index out of bounds.");
        require(bondLevels[levelID].active == false, "Bond Manager: Level is already active.");

        activeBondLevels.push();

        for(uint i = activeBondLevels.length - 1; i >= index; i--) {
            if(i == index) {
                activeBondLevels[i] = levelID;
                break;
            } else {
                activeBondLevels[i] = activeBondLevels[i-1];
            }
        }

        bondLevels[levelID].active = true;

        emit BOND_LEVEL_TOGGLED(levelID, true);
    }

    /// @notice Rearrange bond level in activeBondLevels array.
    /// @param levelID Bond level hex ID.
    /// @param index Index of activeBondLevels array where the Bond level will be rearranged.
    /// @dev Simply it removes the Bond level from the array and it adds it back to the desired index.
    function rearrangeBondLevel(bytes4 levelID, uint256 index) external onlyOwner {
        deactivateBondLevel(levelID);
        activateBondLevel(levelID, index);
    }

    /// @notice Toggle fNFT Bond sale
    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;
        emit SALE_TOGGLED(isSaleActive);
    }

    /// @notice Function the user calls to mint (create) 1 or more fNFT Bonds.
    /// @param levelID level hex ID.
    /// @param amount Desired amount ot be minted.
    /// @param merkleProof merkle proof needed only when a whitelisted discount is active. 
    function createMultipleBondsWithTokens(bytes4 levelID, uint256 amount, bytes32[] calldata merkleProof) public {
        require(isSaleActive, "Bond Manager: Bond sale is inactive.");
        require(amount > 0 && amount <= 20, "Bond Manager: Invalid amount to mint.");
        require(getBondLevel(levelID).active, "Bond Manager: Bond level is inactive.");

        address sender = _msgSender();
        require(sender != address(0), "Bond Manager: Creation to the zero address is prohibited.");

        // Check if bond level has max supply. 
        if(bondLevels[levelID].maxSupply != 0) {
            require(bondLevels[levelID].maxSupply >= bondsSold[levelID] + amount, "Bond Manager: Exceeding Bond level maximum supply.");
            bondsSold[levelID] += amount;
        }

        // Gets price and whether there is a discount.
        (uint256 bondPrice, bool discountActive) = getPrice(levelID);

        // If there is a discount, contract must check that there are enough Bonds left for that discount updateFactor period.
        if(discountActive) { 
            // Check for whitelist & merkle proof.
            if(discount[discountIndex].endWhitelistTime != 0 && discount[discountIndex].endWhitelistTime > block.timestamp) {
                bytes32 leaf = keccak256(abi.encodePacked(sender));
                require(MerkleProof.verify(merkleProof, discount[discountIndex].merkleRoot, leaf), "Bond Manager: You are not whitelisted.");
            }

            uint256 updateFactor = getDiscountUpdateFactor();
            uint256 _bondsSold = uint16(SafeMath.add(discountedBondsSold[discountIndex][updateFactor][levelID], amount));
            require(_bondsSold <= discount[discountIndex].purchaseLimit[levelID], "Bond Manager: Too many bonds minted during this price update period.");

            // If there are, it increments the mapping by the amount being minted.
            discountedBondsSold[discountIndex][updateFactor][levelID] = _bondsSold;
        }

        // Checks that buyer has enough funds to mint the bond.
        require(baseToken.balanceOf(sender) >= bondPrice * amount, "Bond Manager: Your balance can't cover the mint cost.");

        // Transfers funds to trasury contract.
        treasury.bondDeposit(bondPrice * amount, sender);

        // Increments shares metrics.

        // Unweighted shares must be equal to the amount the user pays for the bond. So if the user pays
        // a discounted price, unweighted shares must be discounted as well.
        uint256 unweightedShares = bondPrice;
        // Weighted shares utilizes the actual bond level price despite any discount, otherwise
        // discount would be mathematically inefficient.
        uint256 weightedShares = bondLevels[levelID].price * bondLevels[levelID].weight / WEIGHT_PRECISION;

        totalUnweightedShares += unweightedShares * amount;
        totalWeightedShares += weightedShares * amount;

        userXP[sender] += bondLevels[levelID].price * amount;

        // Call fNFT mintBond function.
        bond.mintBonds(sender, levelID, amount, weightedShares, unweightedShares);
    }

    /// @notice Deposit rewards and shares for users to be claimed from this contract.
    /// @param issuedRewards Amount of rewards to be deposited to the contract claimable by users.
    /// @param issuedShares Amount of new shares claimable by users.
    /// @dev Can only be called by treasury.
    function depositRewards(uint256 issuedRewards, uint256 issuedShares) external {
        require(_msgSender() == address(treasury));

        baseToken.transferFrom(address(treasury), address(this), issuedRewards);

        // Increase accumulated shares and rewards.
        accSharesPerUS += issuedShares * GLOBAL_PRECISION / totalUnweightedShares;
        accRewardsPerWS += issuedRewards * GLOBAL_PRECISION / totalWeightedShares;

        emit REWARDS_DEPOSIT(issuedRewards, issuedShares);
    }

    /// @notice Internal claim function.
    /// @param bondID Unique fNFT Bond uint ID.
    /// @param sender Transaction sender.
    function _claim(uint256 bondID, address sender) internal {
        (uint256 claimableShares, uint256 claimableRewards) = getClaimableAmounts(bondID);
        require((claimableShares != 0 || claimableRewards != 0));

        // the bond.claim() call below will increase the underlying shares for _bondID, thus we must increment the total number of shares as well.
        totalUnweightedShares += claimableShares;
        totalWeightedShares += claimableShares * getBondLevel(bond.getBond(bondID).levelID).weight / WEIGHT_PRECISION;

        // Call fNFT claim function which increments shares and debt for _bondID.
        bond.claim(sender, bondID, claimableRewards, claimableShares);

        // Send rewards to user.
        baseToken.safeTransfer(sender, claimableRewards);
    }

    /// @notice Public implementation of _claim function.
    /// @param bondID Unique fNFT Bond uint ID.
    function claim(uint256 bondID) public {
        _claim(bondID, _msgSender());
    }

    /// @notice Claim rewards and shares for all Bonds owned by the sender.
    /// @dev Should the sender own many bonds, the function will fail due to gas constraints.
    /// Therefore this function will be called from the dAPP only when it verifies that a
    /// user owns a low / moderate amount of Bonds.
    function claimAll() public {
        address sender = _msgSender();

        uint256[] memory bondsIDsOf = bond.getBondsIDsOf(sender);

        for(uint i = 0; i < bondsIDsOf.length; i++) {
            _claim(bondsIDsOf[i], sender);
        }
    }

    /// @notice Claim rewards and shares for Bonds in an array.
    /// @param bondIDs Array of bondIDs that will claim rewards.
    /// @dev If the sender owns many Bonds, calling multiple transactions is necessary.
    /// dAPP will query off-chain (requiring 0 gas) all Bonds IDs owned by the sender.
    /// It will divide the array in smaller chunks and will call this function multiple
    /// times until rewards are claimed for all Bonds. 
    function batchClaim(uint256[] memory bondIDs) public {
        for(uint i = 0; i < bondIDs.length; i++) {
            claim(bondIDs[i]);
        }
    }

    /// @notice Links this bond manager to the fNFT bond at deployment. 
    function linkBondManager() external onlyOwner {
        bond.linkBondManager(address(this));
    }

    /// @notice Sets XP balance for a current user.
    /// @param amount User XP balance.
    /// @param user User address.
    function setUserXP(uint256 amount, address user) external {
        require(_msgSender() == address(bond));
        userXP[user] = amount;
    }

    /// @notice external onlyOnwer implementation of setBaseURI (fNFT Bond function)
    /// @param baseURI string to set as baseURI
    function setBaseURI(string memory baseURI) external onlyOwner {
        return bond.setBaseURI(baseURI);
    }
}