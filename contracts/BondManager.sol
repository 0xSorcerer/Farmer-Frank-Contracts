pragma solidity ^0.8.0;

import "./interfaces/IFNFTBond.sol";

import "./other/Ownable.sol";

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";


contract BondDiscountable {

    uint16 internal discountIndex = 0;
    
    mapping(uint16 => mapping(uint16 => mapping(bytes4 => uint16))) internal discountedBondsSold;

    struct Discount {
        uint256 startTime;
        uint256 endTime;
        uint16 discountRate;
        uint64 updateFrequency;
        mapping(bytes4 => uint8) purchaseLimit;
    }

    mapping(uint16 => Discount) discount;

    function _startDiscount(
        uint256 _startTime,
        uint256 _endTime,
        uint16 _discountRate,
        uint64 _updateFrequency,
        uint8[] memory _purchaseLimit,
        bytes4[] memory _levelIDs
    ) internal {
        uint256 cTime = block.timestamp;
        require(_startTime > cTime, "B01");
        require(_endTime > _startTime, "B02"); 
        require(_updateFrequency < (_endTime - _startTime), "B03"); 
        require((_endTime - _startTime) % _updateFrequency == 0, "B04");
        require(_discountRate <= 100 && _discountRate > 0, "B05");
        require(!isDiscountPlanned(), "B06");
        require(_levelIDs.length == _purchaseLimit.length, "B07");

        discount[discountIndex].startTime = _startTime;
        discount[discountIndex].endTime = _endTime;
        discount[discountIndex].discountRate = _discountRate;
        discount[discountIndex].updateFrequency = _updateFrequency;

        for(uint i = 0; i < _levelIDs.length; i++) {
            discount[discountIndex].purchaseLimit[_levelIDs[i]] = _purchaseLimit[i];
        }
    }

    function _deactivateDiscount() internal {
        discountIndex++;
    }

    function getDiscountUpdateFactor() internal view returns (uint8 updateFactor) {
        uint256 currentTime = block.timestamp;
        updateFactor = uint8((currentTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency);
    }

    function isDiscountPlanned() public view returns (bool) {
        return !(discount[discountIndex].startTime == 0);
    }

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

    IFNFTBond public bond;

    IERC20 public baseToken;

    address public treasury;

    uint256 public totalUnweightedShares;
    uint256 public totalWeightedShares;

    uint256 public accRewardPerWS = 0;
    uint256 public accSharesPerUS = 0;

    uint256 private GLOBAL_PRECISION = 10**18;
    uint256 private WEIGHT_PRECISION = 100;

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

    constructor(address _bond, address _baseToken) {
        bond = IFNFTBond(_bond);
        baseToken = IERC20(_baseToken);
    }

    function startDiscountAt(
        uint256 _startAt,
        uint256 _endAt,
        uint16 _discountRate,
        uint64 _updateFrequency,
        uint8[] memory _purchaseLimit
    ) external onlyOwner {
        _startDiscount(_startAt, _endAt, _discountRate, _updateFrequency, _purchaseLimit, bond.getActiveBondLevels());
        emit CreateDiscount(discountIndex, _startAt, _endAt, _discountRate, _updateFrequency, _purchaseLimit);
    }

    function startDiscountIn(
        uint256 _startIn,
        uint256 _endIn,
        uint16 _discountRate,
        uint64 _updateFrequency,
        uint8[] memory _purchaseLimit
    ) external onlyOwner {
        uint256 cTime = block.timestamp;

        _startDiscount(cTime + _startIn, cTime + _endIn, _discountRate, _updateFrequency, _purchaseLimit, bond.getActiveBondLevels());
        emit CreateDiscount(discountIndex, cTime + _startIn, cTime + _endIn, _discountRate, _updateFrequency, _purchaseLimit);
    }

    function deactivateDiscount() external onlyOwner {
        _deactivateDiscount();
    }

    function addBondLevel(string memory _name, uint16 _basePrice, uint16 _weight) external onlyOwner returns (bytes4) {
        return bond._addBondLevelAtIndex(_name, _basePrice, _weight, bond.totalActiveBondLevels());
    }

    function addBondLevelAtIndex(string memory _name, uint16 _basePrice, uint16 _weight, uint16 _index) external onlyOwner returns (bytes4) {
        return bond._addBondLevelAtIndex(_name, _basePrice, _weight, _index);
    }

    function changeBondLevel(bytes4 levelID, string memory _name, uint16 _basePrice, uint16 _weight) external onlyOwner {
        bond._changeBondLevel(levelID, _name, _basePrice, _weight);
    }

    function deactivateBondLevel(bytes4 levelID) external onlyOwner {
        bond._deactivateBondLevel(levelID);
    }

    function activateBondLevel(bytes4 levelID, uint16 _index) external onlyOwner {
        bond._activateBondLevel(levelID, _index);
    }

    function rearrangeBondLevel(bytes4 levelID, uint16 _index) external onlyOwner {
        bond._deactivateBondLevel(levelID);
        bond._activateBondLevel(levelID, _index);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        return bond.setBaseURI(baseURI_);
    }

    function toggleSale() external onlyOwner {
        isSaleActive = !isSaleActive;
        emit Set(isSaleActive);
    }

    function createMultipleBondsWithTokens(bytes4 levelID, uint16 _amount) public {
        require(isSaleActive);

        address sender = _msgSender();
        require(sender != address(0), "C00");

        (uint256 bondPrice, bool discountActive) = getPrice(levelID);

        if(discountActive) {
            uint8 updateFactor = getDiscountUpdateFactor();
            require(discountedBondsSold[discountIndex][updateFactor][levelID] + _amount <= discount[discountIndex].purchaseLimit[levelID], "C01");
            discountedBondsSold[discountIndex][updateFactor][levelID] += _amount;
        }

        require(baseToken.balanceOf(sender) >= bondPrice * _amount, "C02");

        baseToken.safeTransferFrom(_msgSender(), treasury, bondPrice * _amount);

        totalUnweightedShares += bondPrice * _amount;
        totalWeightedShares += ((bondPrice * bond.getBondLevel(levelID).weight / WEIGHT_PRECISION) * _amount);
        bond.mintBonds(sender, levelID, uint8(_amount), bondPrice);
    }

    function depositRewards(uint256 _issuedRewards, uint256 _issuedShares) external onlyOwner {
        baseToken.transferFrom(_msgSender(), address(this), _issuedRewards);

        accSharesPerUS += _issuedShares * GLOBAL_PRECISION / totalUnweightedShares;
        accRewardPerWS += _issuedRewards * GLOBAL_PRECISION / totalWeightedShares;

        emit Update(_issuedRewards, _issuedShares);
    }

    function _claim(uint256 _bondID, address sender) internal {
        (uint256 claimableShares, uint256 claimableRewards) = getClaimableAmounts(_bondID);
        require((claimableShares != 0 || claimableRewards != 0));

        totalUnweightedShares += claimableShares;
        totalWeightedShares += claimableShares * bond.getBondLevel(bond.getBond(_bondID).levelID).weight / WEIGHT_PRECISION;

        bond.claim(sender, _bondID, claimableRewards, claimableShares);

        baseToken.transferFrom(address(this), sender, claimableRewards);
    }

    function claim(uint256 _bondID) public {
        address sender = _msgSender();
        _claim(_bondID, sender);
    }

    function claimAll() public {
        address sender = _msgSender();

        uint256[] memory bondsIDsOf = bond.getBondsIDsOf(sender);

        for(uint i = 0; i < bondsIDsOf.length; i++) {
            _claim(bondsIDsOf[i], sender);
        }
    }

    function batchClaim(uint256[] memory _bondIDs) public {
        for(uint i = 0; i < _bondIDs.length; i++) {
            claim(_bondIDs[i]);
        }
    }

    function getPrice(bytes4 levelID) public view returns (uint256, bool) {
        uint256 basePrice = SafeMath.mul(bond.getBondLevel(levelID).basePrice, GLOBAL_PRECISION);

        if(isDiscountActive()) {
            uint256 totalUpdates = (discount[discountIndex].endTime - discount[discountIndex].startTime) / discount[discountIndex].updateFrequency;
            uint256 discountStartPrice = basePrice - ((basePrice * discount[discountIndex].discountRate) / 100);
            uint256 updateIncrement = (basePrice - discountStartPrice) / totalUpdates;
            return (discountStartPrice + (updateIncrement * getDiscountUpdateFactor()), true);
        } else {
            return (basePrice, false);
        }
    }

    function getClaimableAmounts(uint256 _bondID) public view returns (uint256 claimableShares, uint256 claimableRewards) {
        IFNFTBond.Bond memory _bond = bond.getBond(_bondID);

        claimableShares = (_bond.unweightedShares * accSharesPerUS / GLOBAL_PRECISION) - _bond.shareDebt;
        claimableRewards = (_bond.weightedShares * accRewardPerWS / GLOBAL_PRECISION) - _bond.rewardDebt;
    }
}