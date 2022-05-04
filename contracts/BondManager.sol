// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IFNFTBond.sol";

import "./other/Ownable.sol";

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";


contract BondDiscountable {

    ///@dev Discount index. Used to map the bonds sold.
    uint16 internal discountIndex = 0;
    
    /// @dev Keep track of how many bonds have been sold during a discount
    /// @dev discountedBondsSold[discountIndex][updateFactor][levelID]
    mapping(uint16 => mapping(uint16 => mapping(bytes4 => uint16))) internal discountedBondsSold;

    /// @notice Info of a discount
    /// @param startTime Timestamp of when discount should start
    /// @param endTime Timestamp of when discount should end
    /// @param discountRate Discount percentage (out of 100)
    /// @param updateFrequency Amount in seconds of how often discount price should update
    /// @param purchaseLimit Mapping of how many bonds per level can be minted every price update.
    struct Discount {
        uint256 startTime;
        uint256 endTime;
        uint16 discountRate;
        uint64 updateFrequency;
        mapping(bytes4 => uint8) purchaseLimit;
    }

    /// @notice discount
    mapping(uint16 => Discount) public discount;

    /// @notice Create a discount
    /// @param _startTime Timestamp at which discount will start 
    /// @param _endTime Timestamp at which discount will end
    /// @param _discountRate Discount percentage (out of 100)
    /// @param _updateFrequency Amount in seconds of how often discount price should update
    /// @param _purchaseLimit Mapping of how many bonds per level can be minted every price update.
    function _startDiscount(
        uint256 _startTime,
        uint256 _endTime,
        uint16 _discountRate,
        uint64 _updateFrequency,
        uint8[] memory _purchaseLimit,
        bytes4[] memory _levelIDs
    ) internal {
        uint256 cTime = block.timestamp;
        require(_startTime > cTime, "Bond Discountable: Start timestamp must be > than current timestamp.");
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

    /// @notice Deactivate and cancel the discount
    function _deactivateDiscount() internal {
        discountIndex++;
    }

    /// @notice Returns the discount updateFactor
    /// updateFactor is the nth discount price update
    function getDiscountUpdateFactor() internal view returns (uint8 updateFactor) {
        uint256 currentTime = block.timestamp;
        updateFactor = uint8((currentTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency);
    }

    /// @notice Returns whether a discount is planned for the future
    function isDiscountPlanned() public view returns (bool) {
        return !(discount[discountIndex].startTime == 0);
    }

    /// @notice Returns whether a discount is currently active
    function isDiscountActive() public view returns (bool) {
        if (isDiscountPlanned()) {
            uint256 cTime = block.timestamp;
            if (
                discount[discountIndex].startTime < cTime &&
                discount[discountIndex].endTime > cTime
            ) {
                return true;
            }
        }

        return false;
    }
}

contract BondManager is Ownable, BondDiscountable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice fNFT Bond interface.
    IFNFTBond public bond;

    /// @notice Token used to mint Bonds and issue rewards.
    IERC20 public baseToken;

    /// @notice Treasury address to send bonded assets.
    address public treasury;

    /// @notice Total number of unweighted shares.
    uint256 public totalUnweightedShares;
    /// @notice Total number of weighted shares.
    uint256 public totalWeightedShares;

    /// @notice Accumulated rewards per weigted shares. Used to calculate rewardDebt.
    uint256 public accRewardsPerWS = 0;
    /// @notice Accumulated shares per unweighted shares. Used to calculate shareDebt.
    uint256 public accSharesPerUS = 0;

    /// @dev Precision constants.
    uint256 private GLOBAL_PRECISION = 10**18;
    uint256 private WEIGHT_PRECISION = 100;

    /// @notice Whether bonds can be currently minted.
    bool public isSaleActive = true;

    event CreateDiscount (
        uint16 indexed discountIndex,
        uint256 startTime,
        uint256 endTime,
        uint16 discountRate,
        uint64 updateFrequency,
        uint8[] purchaseLimit
    );

    event Set (
        bool isSaleActive
    );

    event Update (
        uint256 issuedRewards,
        uint256 issuedShares
    );

    /// @param _bond fNFT Bond contract address.
    /// @param _baseToken Base Token contract address.
    constructor(address _bond, address _baseToken) {
        require(_bond != address(0));
        require(_baseToken != address(0));

        bond = IFNFTBond(_bond);
        baseToken = IERC20(_baseToken);
    }

    /// @notice external onlyOwner implementation of _startDiscount (BondDiscountable) function.
    /// @param _startAt Timestamp at which the discount will start.
    /// @param _endAt Timestamp at which the discount will end.
    /// @param _discountRate Discount percentage (out of 100).
    /// @param _updateFrequency Amount in seconds of how often discount price should update.
    /// @param _purchaseLimit Array of how many bonds per level can be minted every price update.
    function startDiscountAt(uint256 _startAt, uint256 _endAt, uint16 _discountRate, uint64 _updateFrequency, uint8[] memory _purchaseLimit) external onlyOwner {
        _startDiscount(_startAt, _endAt, _discountRate, _updateFrequency, _purchaseLimit, bond.getActiveBondLevels());
        emit CreateDiscount(discountIndex, _startAt, _endAt, _discountRate, _updateFrequency, _purchaseLimit);
    }

    /// @notice external onlyOwner implementation of _startDiscount (BondDiscountable) function.
    /// @param _startIn Amount of seconds until the discount start.
    /// @param _endIn Amount of seconds until the discount end.
    /// @param _discountRate Discount percentage (out of 100).
    /// @param _updateFrequency Amount in seconds of how often discount price should update.
    /// @param _purchaseLimit Array of how many bonds per level can be minted every price update.
    function startDiscountIn(uint256 _startIn, uint256 _endIn, uint16 _discountRate, uint64 _updateFrequency, uint8[] memory _purchaseLimit) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startDiscount(cTime + _startIn, cTime + _endIn, _discountRate, _updateFrequency, _purchaseLimit, bond.getActiveBondLevels());
        emit CreateDiscount(discountIndex, cTime + _startIn, cTime + _endIn, _discountRate, _updateFrequency, _purchaseLimit);
    }

    /// @notice external onlyOwner implementation of _deactivateDiscount (BondDiscountable) function
    function deactivateDiscount() external onlyOwner {
        _deactivateDiscount();
    }

    /// @notice external onlyOwner implementation of _addBondLevelAtIndex (fNFT Bond) function.
    /// @param _name Bond level name. Showed on Farmer Frank's UI.
    /// @param _basePrice Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
    /// @param _weight Weight percentage of Bond level (>= 100).
    /// @dev Doesn't take _index as a parameter and appends the Bond level at the end of the active levels array.
    function addBondLevel(string memory _name, uint16 _basePrice, uint16 _weight, uint32 _sellableAmount) external onlyOwner returns (bytes4) {
        return bond._addBondLevelAtIndex(_name, _basePrice, _weight,  _sellableAmount, bond.totalActiveBondLevels());
    }

    /// @notice external onlyOwner implementation of _addBondLevelAtIndex (fNFT Bond) function.
    /// @param _name Bond level name. Showed on Farmer Frank's UI.
    /// @param _basePrice Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
    /// @param _weight Weight percentage of Bond level (>= 100).
    /// @param _index Index of activeBondLevels array where the Bond level will be inserted.
    function addBondLevelAtIndex(string memory _name, uint16 _basePrice, uint16 _weight, uint32 _sellableAmount, uint16 _index) external onlyOwner returns (bytes4) {
        return bond._addBondLevelAtIndex(_name, _basePrice, _weight, _sellableAmount, _index);
    }

    /// @notice external onlyOwner implementation of _changeBondLevel (fNFT Bond) function.
    /// @param levelID Bond level hex ID being changed.
    /// @param _name New Bond level name.
    /// @param _basePrice New Bond base price.
    /// @param _weight New Weight percentage of Bond level (>= 100).
    function changeBondLevel(bytes4 levelID, string memory _name, uint16 _basePrice, uint16 _weight, uint32 _sellableAmount) external onlyOwner {
        bond._changeBondLevel(levelID, _name, _basePrice, _weight, _sellableAmount);
    }

    /// @notice external onlyOwner implementation of _deactivateBondLevel (fNFT Bond) function.
    /// @param levelID Bond level hex ID.
    function deactivateBondLevel(bytes4 levelID) external onlyOwner {
        bond._deactivateBondLevel(levelID);
    }

    /// @notice external onlyOwner implementation of _activateBondLevel (fNFT Bond) function.
    /// @param levelID Bond level hex ID.
    /// @param _index Index of activeBondLevels array where the Bond level will be inserted.
    function activateBondLevel(bytes4 levelID, uint16 _index) external onlyOwner {
        bond._activateBondLevel(levelID, _index);
    }

    /// @notice Rearrange bond level in activeBondLevels array.
    /// @param levelID Bond level hex ID.
    /// @param _index Index of activeBondLevels array where the Bond level will be rearranged.
    /// @dev Simply it removes the Bond level from the array and it adds it back to the desired index.
    function rearrangeBondLevel(bytes4 levelID, uint16 _index) external onlyOwner {
        bond._deactivateBondLevel(levelID);
        bond._activateBondLevel(levelID, _index);
    }

    /// @notice external onlyOnwer implementation of setBaseURI (fNFT Bond function)
    /// @param baseURI_ string to set as baseURI
    function setBaseURI(string memory baseURI_) external onlyOwner {
        return bond.setBaseURI(baseURI_);
    }

    /// @notice Toggle fNFT Bond sale
    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;
        emit Set(isSaleActive);
    }

    /// @notice Public function that users will be utilizing to mint their Bond.
    /// @param levelID Bond level hex ID (provided by the dAPP or retreived through getActiveBondLevels() in fNFT Bond contract).
    /// @param _amount Amount of fNFT Bonds being minted. Remember there is a limit of 20 Bonds per transaction.
    function createMultipleBondsWithTokens(bytes4 levelID, uint16 _amount) public {
        require(isSaleActive);
        require(_amount > 0);

        address sender = _msgSender();
        require(sender != address(0), "fNFT Bond Manager: Creation from the zero address is prohibited.");

        // Gets price and whether there is a discount.
        (uint256 bondPrice, bool discountActive) = getPrice(levelID);

        // If there is a discount, contract must check that there are enough Bonds left for that discount updateFactor period.
        if(discountActive) {
            uint8 updateFactor = getDiscountUpdateFactor();
            uint16 _bondsSold = uint16(SafeMath.add(discountedBondsSold[discountIndex][updateFactor][levelID], _amount));
            require(_bondsSold <= discount[discountIndex].purchaseLimit[levelID], "C01");

            // If there are, it increments the mapping by the amount being minted.
            discountedBondsSold[discountIndex][updateFactor][levelID] = _bondsSold;
        }

        // Checks that buyer has enough funds to mint the bond.
        require(baseToken.balanceOf(sender) >= bondPrice * _amount, "C02");

        // Transfers funds to trasury contract.
        baseToken.safeTransferFrom(_msgSender(), address(this), SafeMath.mul(bondPrice, _amount));

        // Increments shares metrics.
        totalUnweightedShares += bondPrice * _amount;
        totalWeightedShares += ((bondPrice * bond.getBondLevel(levelID).weight / WEIGHT_PRECISION) * _amount);

        // Call fNFT mintBond function.
        bond.mintBonds(sender, levelID, uint8(_amount), bondPrice);
        
    }

    /// @notice Deposit rewards and shares for users to be claimed to this contract.
    /// @param _issuedRewards Amount of rewards to be deposited to the contract claimable by users.
    /// @param _issuedShares Amount of new shares claimable by users.
    function depositRewards(uint256 _issuedRewards, uint256 _issuedShares) external onlyOwner {
        //require(_msgSender() == treasury);

        // Transfer funds from treasury to contract.
        //baseToken.transferFrom(treasury, address(this), _issuedRewards);

        baseToken.transferFrom(_msgSender(), address(this), _issuedRewards);

        // Increase accumulated shares and rewards.
        accSharesPerUS += _issuedShares * GLOBAL_PRECISION / totalUnweightedShares;
        accRewardsPerWS += _issuedRewards * GLOBAL_PRECISION / totalWeightedShares;

        emit Update(_issuedRewards, _issuedShares);
    }

    /// @notice Internal claim function.
    /// @param _bondID Unique fNFT Bond uint ID.
    /// @param sender Transaction sender.
    function _claim(uint256 _bondID, address sender) internal {
        (uint256 claimableShares, uint256 claimableRewards) = getClaimableAmounts(_bondID);
        require((claimableShares != 0 || claimableRewards != 0));

        // the bond.claim() call below will increase the underlying shares for _bondID, thus we must increment the total number of shares as well.
        totalUnweightedShares += claimableShares;
        totalWeightedShares += claimableShares * bond.getBondLevel(bond.getBond(_bondID).levelID).weight / WEIGHT_PRECISION;

        // Call fNFT claim function which increments shares and debt.
        bond.claim(sender, _bondID, claimableRewards, claimableShares);

        // Send rewards to user.
        baseToken.transfer(sender, claimableRewards);
    }

    /// @notice Public implementation of _claim function.
    /// @param _bondID Unique fNFT Bond uint ID.
    function claim(uint256 _bondID) public {
        address sender = _msgSender();
        _claim(_bondID, sender);
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
    /// @dev If the sender owns many Bonds, calling multiple transactions is necessary.
    /// dAPP will query off-chain (requiring 0 gas) all Bonds IDs owned by the sender.
    /// It will divide the array in smaller chunks and will call this function multiple
    /// times until rewards are claimed for all Bonds. 
    function batchClaim(uint256[] memory _bondIDs) public {
        for(uint i = 0; i < _bondIDs.length; i++) {
            claim(_bondIDs[i]);
        }
    }

    /// @notice Get the price for a particular Bond level.
    /// @param levelID Bond level hex ID
    function getPrice(bytes4 levelID) public view returns (uint256, bool) {
        // Multiplies base price by GLOBAL_PRECISION (token decimals)
        
        uint256 basePrice = (bond.getBondLevel(levelID).basePrice * GLOBAL_PRECISION);
        if(isDiscountActive()) {
            // Calculates total number of price updates during the discount time frame.
            uint256 totalUpdates = (discount[discountIndex].endTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
            // Calculates the price when discount starts: the lowest price. Simply, the base price discounted by the discount rate.
            uint256 discountStartPrice = basePrice - ((basePrice * discount[discountIndex].discountRate) / 100);
            // Calculates how much price will increase at every price update.
            uint256 updateIncrement = (basePrice - discountStartPrice) / totalUpdates;
            // Finally calcualtes the price using the above variables.
            return (discountStartPrice + (updateIncrement * getDiscountUpdateFactor()), true);
        } else {
            return (basePrice, false);
        }
        
    }

    /// @notice Get claimable amount of shares and rewards for a particular Bond.
    /// @param _bondID Unique fNFT Bond uint ID
    function getClaimableAmounts(uint256 _bondID) public view returns (uint256 claimableShares, uint256 claimableRewards) {
        IFNFTBond.Bond memory _bond = bond.getBond(_bondID);

        claimableShares = (_bond.unweightedShares * accSharesPerUS / GLOBAL_PRECISION) - _bond.shareDebt;
        claimableRewards = (_bond.weightedShares * accRewardsPerWS / GLOBAL_PRECISION) - _bond.rewardDebt;
    }

    function linkBondManager() external onlyOwner {
        bond._linkBondManager(address(this));
    }
}