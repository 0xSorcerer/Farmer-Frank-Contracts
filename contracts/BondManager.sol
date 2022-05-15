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
        bytes4 levelID;
        bool active;
        uint256 weight;
        uint256 maxSupply;
        string name;
        uint256 price;
    }

    IFNFTBond public bond;

    IERC20 public baseToken;

    uint256 public accRewardsPerWS = 0;
    uint256 public accSharesPerUS = 0;

    uint256 private GLOBAL_PRECISION = 10**18;
    uint256 private WEIGHT_PRECISION = 100;

    bool public isSaleActive = true;

    uint256 private constant MAX_BOND_LEVELS = 10;

    uint256 public PRECISION  = 1e18;

    bytes4[] private activeBondLevels;

    mapping(bytes4 => BondLevel) private bondLevels;

    mapping(bytes4 => uint256) private bondsSold;

    mapping(address => uint256) private userXP;

    uint fixedPrecision = 5;

    struct User {
        uint256 unweightedShares;
        uint256 weightedShares;
        uint256 shareDebt;
        uint256 rewardDebt;
        uint256 XP;
        uint256 index;
    }

    uint256 public index = PRECISION;

    uint256 public totalOutstandingUS;
    uint256 public totalOutstandingWS;
    uint256 public totalCirculatingUS;
    uint256 public totalCirculatingWS;

    uint256 public totalUnweightedShares;
    uint256 public totalWeightedShares;

    mapping(address => User) public users ;

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

    constructor(address _bond, address _baseToken) {
        require(_bond != address(0));
        require(_baseToken != address(0));

        bond = IFNFTBond(_bond);
        baseToken = IERC20(_baseToken);

        addBondLevelAtIndex("Level I", 100, 0, activeBondLevels.length, SafeMath.mul(10, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level II", 105, 0, activeBondLevels.length, SafeMath.mul(100, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level III", 110, 0, activeBondLevels.length, SafeMath.mul(1000, GLOBAL_PRECISION));
        addBondLevelAtIndex("Level IV", 115, 0, activeBondLevels.length, SafeMath.mul(5000, GLOBAL_PRECISION));
    }


    function createMultipleBondsWithTokens(bytes4 levelID, uint256 amount, bytes32[] calldata merkleProof) public {
        require(isSaleActive, "Bond Manager: Bond sale is inactive.");
        require(amount > 0 && amount <= 20, "Bond Manager: Invalid amount to mint.");
        require(getBondLevel(levelID).active, "Bond Manager: Bond level is inactive.");

        address sender = _msgSender();
        require(sender != address(0), "Bond Manager: Creation to the zero address is prohibited.");

        if(bondLevels[levelID].maxSupply != 0) {
            require(bondLevels[levelID].maxSupply >= bondsSold[levelID] + amount, "Bond Manager: Exceeding Bond level maximum supply.");
            bondsSold[levelID] += amount;
        }

        (uint256 bondPrice, bool discountActive) = getPrice(levelID);
        
        if(discountActive) { 
            if(discount[discountIndex].endWhitelistTime != 0 && discount[discountIndex].endWhitelistTime > block.timestamp) {
                bytes32 leaf = keccak256(abi.encodePacked(sender));
                require(MerkleProof.verify(merkleProof, discount[discountIndex].merkleRoot, leaf), "Bond Manager: You are not whitelisted.");
            }

            uint256 updateFactor = getDiscountUpdateFactor();
            uint256 _bondsSold = uint16(SafeMath.add(discountedBondsSold[discountIndex][updateFactor][levelID], amount));
            require(_bondsSold <= discount[discountIndex].purchaseLimit[levelID], "Bond Manager: Too many bonds minted during this price update period.");

            discountedBondsSold[discountIndex][updateFactor][levelID] = _bondsSold;
        }

        //require(baseToken.balanceOf(sender) >= bondPrice * amount, "Bond Manager: Your balance can't cover the mint cost.");

        //treasury.bondDeposit(bondPrice * amount, sender);

        // Gets it to string precision
        uint256 unweightedShares = bondLevels[levelID].price * amount;
        uint256 weightedShares = bondLevels[levelID].price * amount * bondLevels[levelID].weight / 100;

        totalOutstandingUS += unweightedShares;
        totalOutstandingWS += weightedShares;
        totalCirculatingUS += unweightedShares;
        totalCirculatingWS += unweightedShares;

        totalUnweightedShares += unweightedShares;
        totalWeightedShares += weightedShares;

        if(users[sender].index == 0) {
            users[sender].index = 1e18;
        }

        users[sender].unweightedShares += unweightedShares;
        users[sender].weightedShares += weightedShares;
        users[sender].shareDebt = users[sender].unweightedShares * accSharesPerUS / PRECISION;
        users[sender].rewardDebt = users[sender].weightedShares * accRewardsPerWS / PRECISION;
        users[sender].XP += bondLevels[levelID].price;

        bond.mintBonds(sender, levelID, users[sender].index, amount);
        
    }

    function depositRewards(uint256 issuedRewards, uint256 issuedShares) external {
        //require(_msgSender() == address(treasury));

        baseToken.transferFrom(_msgSender(), address(this), issuedRewards);

        // Increase accumulated shares and rewards.

        // issuedRewards and issuedShares are 10e18 now, they must be 10e23

        accSharesPerUS += issuedShares * PRECISION / totalUnweightedShares;
        accRewardsPerWS += issuedRewards * PRECISION / totalWeightedShares;

        index = (index * ((issuedShares * PRECISION / totalOutstandingUS) + PRECISION)) / PRECISION;

        uint256 weight = (totalWeightedShares * PRECISION / totalUnweightedShares);

        totalOutstandingUS += issuedShares;
        totalOutstandingWS += issuedRewards * weight / PRECISION;

        //
        //totalUnweightedShares += issuedShares * 1e5;
        //totalWeightedShares += (issuedRewards * 1e5) * weight / STRONG_PRECISION;

        emit REWARDS_DEPOSIT(issuedRewards, issuedShares);
    }

    function getClaimableAmounts(address user) public view returns (uint256 claimableShares, uint256 claimableRewards) {
        claimableShares = (users[user].unweightedShares * accSharesPerUS / PRECISION) - users[user].shareDebt;
        claimableRewards = (users[user].weightedShares * accRewardsPerWS / PRECISION) - users[user].rewardDebt;
    }

    function dataTransfer(address from, address to, uint256 bondID) public {
        //(uint256 unweightedShares, uint256 weightedShares) = bond.getBondShares(bondID);
        uint256 unweightedShares = getBondShares(bondID);

        claim(from);
        claim(to);

        uint256 previousIndex = users[from].index * GLOBAL_PRECISION / bond.getBond(bondID).index;
        uint256 newIndex = users[to].index * GLOBAL_PRECISION / previousIndex;

        if (IERC721(address(bond)).balanceOf(from) == 1) {
            users[from].unweightedShares = 0;
            users[from].weightedShares = 0;
            users[from].shareDebt = 0;
            users[from].rewardDebt = 0;
            users[from].XP = 0;
            users[from].index = 1e18;
        } else {
            users[from].unweightedShares -= unweightedShares;
            //users[from].weightedShares -= weightedShares;
            users[from].shareDebt = users[from].unweightedShares * accSharesPerUS / PRECISION;
            users[from].rewardDebt = users[from].weightedShares * accRewardsPerWS / PRECISION;
            users[from].XP = users[from].XP - getBondLevel(bond.getBond(bondID).levelID).price;
        }

        users[to].unweightedShares += unweightedShares;
        //users[to].weightedShares += weightedShares;
        users[to].shareDebt = users[to].unweightedShares * accSharesPerUS / PRECISION;
        users[to].rewardDebt = users[to].weightedShares * accRewardsPerWS / PRECISION;
        users[to].XP = users[to].XP + getBondLevel(bond.getBond(bondID).levelID).price;

        bond.setBondIndex(bondID, newIndex);
    }

    function claim(address user) public {

        (uint256 claimableShares, uint256 claimableRewards) = getClaimableAmounts(user);

        if(users[user].index == 0) {
            users[user].index = 1e18;
        }
        
        if(claimableShares == 0 && claimableRewards == 0) {
            return;
        }

        uint256 userWeight = (users[user].weightedShares * PRECISION / users[user].unweightedShares);

        users[user].index = (users[user].index * ((claimableShares * GLOBAL_PRECISION / users[user].unweightedShares) + GLOBAL_PRECISION)) / GLOBAL_PRECISION;
        
        users[user].unweightedShares += claimableShares;
        users[user].weightedShares += (claimableShares * userWeight / PRECISION);

        users[user].shareDebt = users[user].unweightedShares * accSharesPerUS / PRECISION;
        users[user].rewardDebt = users[user].weightedShares * accRewardsPerWS / PRECISION;

        totalCirculatingUS += claimableShares;
        totalCirculatingWS += (claimableShares * userWeight / PRECISION);

        totalUnweightedShares += claimableShares;
        totalWeightedShares += (claimableShares * userWeight / PRECISION);

        baseToken.safeTransfer(user, claimableRewards);
    }

    function getBondShares(uint256 bondID) public view returns (uint256) {
        address bondOwner = IERC721(address(bond)).ownerOf(bondID);
        return (users[bondOwner].index * GLOBAL_PRECISION / bond.getBond(bondID).index * getBondLevel(bond.getBond(bondID).levelID).price) / GLOBAL_PRECISION;
    }

    function getActiveBondLevels() public view returns (bytes4[] memory) {
        return activeBondLevels;
    }

    function getBondLevel(bytes4 levelID) public view returns (BondLevel memory) {
       return bondLevels[levelID];
    }

    function getUserXP(address user) external view returns (uint256) {
        return userXP[user];
    }

    function getPrice(bytes4 levelID) public view returns (uint256, bool) {
        uint256 price = getBondLevel(levelID).price;

        if(isDiscountActive()) {
            uint256 totalUpdates = (discount[discountIndex].endTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
            uint256 discountStartPrice = price - ((price * discount[discountIndex].discountRate) / 100);
            uint256 updateIncrement = (price - discountStartPrice) / totalUpdates;
            return (discountStartPrice + (updateIncrement * getDiscountUpdateFactor()), true);
        } else {
            return (price, false);
        }
    }

    function startDiscountAt(uint256 startAt, uint256 endAt, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startDiscount(startAt, endAt, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, startAt, endAt, discountRate, false);
    }

    function startDiscountIn(uint256 startIn, uint256 endIn, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startDiscount(cTime + startIn, cTime + endIn, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, cTime + startIn, cTime + endIn, discountRate, false);
    }

    function startWhitelistedDiscountAt(uint256 startAt, uint256 endWhitelistAt, uint256 endAt, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        _startWhitelistedDiscount(startAt, endWhitelistAt, endAt, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, startAt, endAt, discountRate, true);
    }

    function startWhitelistedDiscountIn(uint256 startIn, uint256 endWhitelistIn, uint256 endIn, bytes32 merkleRoot, uint16 discountRate, uint240 updateFrequency, uint256[] memory purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startWhitelistedDiscount(cTime + startIn, cTime + endWhitelistIn, cTime + endIn, merkleRoot, discountRate, updateFrequency, purchaseLimit, getActiveBondLevels());
        emit DISCOUNT_CREATED(discountIndex, cTime + startIn, cTime + endIn, discountRate, true);
    }


    function deactivateDiscount() external onlyOwner {
        _deactivateDiscount();
    }

    function addBondLevelAtIndex(string memory name, uint256 weight, uint256 maxSupply, uint256 index, uint256 price) public onlyOwner returns (bytes4) {
        require(!isDiscountPlanned(), "Bond Manager: Can't add bond level during a discount.");
        require(MAX_BOND_LEVELS > activeBondLevels.length, "Bond Manager: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(index <= activeBondLevels.length, "Bond Manager: Index out of bounds.");

        bytes4 levelID = bytes4(keccak256(abi.encodePacked(name, weight, block.timestamp, price)));

        BondLevel memory bondLevel = BondLevel({
            levelID: levelID,
            active: true,
            weight: weight,
            maxSupply: maxSupply,
            name: name,
            price: price
        });


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

    function addBondLevel(string memory name, uint256 weight, uint256 maxSupply, uint256 price) external onlyOwner returns (bytes4) {
        return addBondLevelAtIndex(name, weight, maxSupply, activeBondLevels.length, price);
    }

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

    function deactivateBondLevel(bytes4 levelID) public onlyOwner {
        require(!isDiscountPlanned(), "Bond Manager: Can't deactivate bond level during a discount.");
        require(bondLevels[levelID].active == true, "Bond Manager: Level is already inactive.");

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

    function rearrangeBondLevel(bytes4 levelID, uint256 index) external onlyOwner {
        deactivateBondLevel(levelID);
        activateBondLevel(levelID, index);
    }

    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;
        emit SALE_TOGGLED(isSaleActive);
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

    function toFixed(uint256 number, uint n) public view returns (uint256) {

        if (number == 0) {
            return 0;
        }

        uint precision = 23;
        uint length = numDigits(number);
        
        uint x;

        if(length < precision) {
           x = length - ( n - (precision - length)) ;
        } else {
            x = (length - ((length - precision) + n));
        }
        
        return number / 10 ** x * 10 ** x;
    }

    function numDigits(uint number) public view returns (uint8) {
            uint8 digits = 0;
            //if (number < 0) digits = 1; // enable this line if '-' counts as a digit
            while (number != 0) {
                number /= 10;
                digits++;
            }
        return digits;
    }

    
}