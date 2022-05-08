// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/ERC721.sol";
import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";

/*
    TODO: 
        TRANSFER RESET EARNED
*/

// ERC721 implementation for Farmer Frank NFT Bonds (Perpetuities). 
// Author: @0xSorcerer

/// @notice Users are not supposed to interract with this contract. Most functions are marked
/// as onlyOwner, where the contract owner will be a BondManager contract. Users will use the BondManager
/// contract to mint and claim, which will call the functions in this contract.

contract fNFTBond is ERC721, Ownable {

    using SafeMath for uint256;
    using Address for address;

    /// @notice Info of each fNFT Bond.
    struct Bond {
        // Unique fNFT Bond uint ID.
        uint256 bondID;
        // Mint timestamp.
        uint48 mint;
        // Unique fNFT Bond level hex ID.
        bytes4 levelID;
        // fNFT Bond level weight.
        // Storing weight in bond object to save gas. Allows to avoid getBondLevel() call in BondManager contract.
        uint16 weight;
        // Amount of REWARDS (not shares) earned historically when holding contract. Resets on _transfer().
        uint256 earned;
        // Amount of unweighted shares.
        uint256 unweightedShares;
        // Amount of weighted shares.
        uint256 weightedShares;
        // Reward debt (JOE token reward debt).
        uint256 rewardDebt;
        // Share debt (Bond shares reward debt).
        uint256 shareDebt;
    }

    struct BondLevel {
        // Unique fNFT Bond level hex ID.
        bytes4 levelID;
        // Whether bonds of this level can be currently minted.
        bool active;
        // Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
        uint16 basePrice;
        // Bond weight multipliers. Used to calculate weighted shares.
        // Weight is percentage (out of 100), hence weight = 100 would mean 1x (base multiplier).
        // This is why WEIGHT_PRECISION = 100. 
        uint16 weight;
        // Maximum supply of bonds of that level. If set to 0, the maximum supply is unlimited.
        uint64 sellableAmount;
        // Bond level name used on Farmer Frank's UI.
        string name;
    }

    /// @notice Bond manager interface used to get accSharesPerUS() and accRewardsPerWS().
    IBondManager public bondManager;

    /// @dev Precision constants
    uint256 internal constant GLOBAL_PRECISION = 10**18;
    uint256 internal constant WEIGHT_PRECISION = 100;

    /// @dev Maximum amount of Bond levels the bond can support.
    uint16 internal constant MAX_BOND_LEVELS = 10;

    /// @dev Mapping storing all bonds data.
    mapping(uint256 => Bond) private bonds; 
    /// @dev Mapping storing all existing Bond levels.
    mapping(bytes4 => BondLevel) private bondLevels;
    /// @dev Array storing all active bonds level: bonds that can be minted. 
    bytes4[] private activeBondLevels;
    /// @dev Mapping to store how many bonds were minted per level. Used only for bonds with maximum supply.
    mapping(bytes4 => uint256) private bondsSold;
    /// @notice Amount of currently active Bond levels
    /// @dev Must be <= MAX_BOND_LEVELS
    uint8 public totalActiveBondLevels;

    event NewBondLevel (
        bytes4 indexed levelID,
        uint16 basePrice,
        uint16 weight,
        string name
    );

    event BondLevelChanged (
        bytes4 indexed levelID,
        uint16 basePrice,
        uint16 weight,
        string name
    );

    event BondLevelDeactivated (
        bytes4 indexed levelID
    );

    event BondLevelActivated (
        bytes4 indexed levelID
    );

    event BondCreated (
        uint256 indexed bondID,
        bytes4 indexed levelID,
        address indexed account,
        uint48 mint,
        uint256 price
    );

    event Claim (
        uint256 indexed bondID,
        address indexed account,
        uint256 issuedShares,
        uint256 issuedRewards
    );

    /// @param name fNFT token name: fNFT Bond - (JOE).
    /// @param symbol fNFT token symbol: fNFTB.
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        _setBaseURI("https://gist.githubusercontent.com/0xSorcerer/3a9caa1af932f7b4ea57b7a7ef73494c/raw/dfdaa22b1f6c5847e4ad07b46fb57aecdb5d3d99/gistfile1.json");

        //Create initial Bond levels.
        _addBondLevelAtIndex("Level I", 10, 100, 0, totalActiveBondLevels);
        _addBondLevelAtIndex("Level II", 100, 105, 0, totalActiveBondLevels);
        _addBondLevelAtIndex("Level III", 1000, 110, 0, totalActiveBondLevels);
        _addBondLevelAtIndex("Level IV", 5000, 115, 0, totalActiveBondLevels);
    }

    /// @notice Create a Bond level and add it at a particular index of activeBondLevels array.
    /// @param _name Bond level name. Showed on Farmer Frank's UI.
    /// @param _basePrice Bond base price. Meaning that price doesn't take into account decimals (ex 10**18).
    /// @param _weight Weight percentage of Bond level (>= 100).
    /// @param _index Index of activeBondLevels array where the Bond level will be inserted.
    /// @dev onlyOwner: Function can be called only by BondManager contract.
    /// @dev If the Bond level must be added at the end of the array --> _index = totalActiveBondLevels.
    /// @dev When adding a bond level whose index isn't totalActiveBondLevels, the contract loops through
    /// the array shifting its elements. We disregard unbounded gas cost possible error as the contract
    /// is designed to store a "concise" amount of Bond levels: 10. Hence Avalanche would be totally able
    /// to run the transaction.
    function _addBondLevelAtIndex(string memory _name, uint16 _basePrice, uint16 _weight, uint32 _sellableAmount, uint16 _index) public onlyOwner returns (bytes4) {
        require(MAX_BOND_LEVELS > totalActiveBondLevels, "fNFT Bond: Exceeding the maximum amount of Bond levels. Try deactivating a level first.");
        require(_index <= totalActiveBondLevels, "fNFT Bond: Index out of bounds.");

        // Calculate unique Bond level hex ID.
        bytes4 levelID = bytes4(keccak256(abi.encodePacked(_name, _basePrice, _weight, block.timestamp)));

        BondLevel memory _level = BondLevel({
            levelID: levelID,
            active: true,
            basePrice: _basePrice,
            weight: _weight,
            sellableAmount: _sellableAmount,
            name: _name
        });

        // Dealing with activeBondLevels elements shift to add Bond level at desired _index.

        activeBondLevels.push();

        for(uint i = activeBondLevels.length - 1; i >= _index; i--) {
            if(i == _index) {
                activeBondLevels[i] = levelID;
                break;
            } else {
                activeBondLevels[i] = activeBondLevels[i-1];
            }
        }
        
        bondLevels[levelID] = _level;
        totalActiveBondLevels++;

        emit NewBondLevel(levelID, _basePrice, _weight, _name);
        
        return(levelID);
    }

    /// @notice Change a Bond level.
    /// @param levelID Bond level hex ID being changed.
    /// @param _name New Bond level name.
    /// @param _basePrice New Bond base price.
    /// @param _weight New Weight percentage of Bond level (>= 100).
    function _changeBondLevel(bytes4 levelID, string memory _name, uint16 _basePrice, uint16 _weight, uint32 _sellableAmount) external onlyOwner {
        bondLevels[levelID] = BondLevel({
            levelID: levelID,
            active: true,
            basePrice: _basePrice,
            weight: _weight,
            sellableAmount: _sellableAmount,
            name: _name
        });

        emit BondLevelChanged(levelID, _basePrice, _weight, _name);
    }

    /// @notice Deactivate a Bond level.
    /// @param levelID Bond level hex ID.
    /// @dev onlyOwner: Function can be called only by BondManager contract.
    /// @dev Bond being deactivated is removed from activeBondLevels array and its active parameter
    /// is set to false.
    /// @dev When removing a bond level, the contract loops through the activeBondLevels array shifting its elements.
    /// We disregard unbounded gas cost possible error as the contract is designed to store a "concise"
    /// amount of Bond levels: 10. Hence Avalanche would be totally able to run the transaction.
    function _deactivateBondLevel(bytes4 levelID) external onlyOwner {
        require(bondLevels[levelID].active == true, "A04");

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
        totalActiveBondLevels--;
        emit BondLevelDeactivated(levelID);
    }

    /// @notice Activate a Bond level. Bond level activation & deactivation can serve to introduce interesting mechanics.
    /// For instance, Limited Edition levels can be introduced. They can be active for limited periods of time, enabling
    /// Farmer Frank's Team to manage their availability at will. 
    /// @param levelID Bond level hex ID.
    /// @param _index Index of activeBondLevels array where the Bond level will be inserted.
    /// @dev onlyOwner: Function can be called only by BondManager contract.
    /// @dev When activating a bond level, the contract loops through the activeBondLevels array shifting its elements.
    /// We disregard unbounded gas cost possible error as the contract is designed to store a "concise"
    /// amount of Bond levels: 10. Hence Avalanche would be totally able to run the transaction.
    function _activateBondLevel(bytes4 levelID, uint16 _index) external onlyOwner {
        require(!(totalActiveBondLevels >= MAX_BOND_LEVELS), "A05");
        require(_index <= totalActiveBondLevels, "A06");
        require(bondLevels[levelID].active == false, "A07");

        activeBondLevels.push();

        for(uint i = activeBondLevels.length - 1; i >= _index; i--) {
            if(i == _index) {
                activeBondLevels[i] = levelID;
                break;
            } else {
                activeBondLevels[i] = activeBondLevels[i-1];
            }
        }

        bondLevels[levelID].active = true;
        totalActiveBondLevels++;
        emit BondLevelActivated(levelID);
    }

    /// @notice Connect fNFT Bond contract (this) to its manager. Manager is needed to get accSharesPerUS() and accRewardsPerWS().
    function _linkBondManager(address _bondManager) external onlyOwner {
        require(_bondManager != address(0), "fNFT Bond: Bond manager can't be set to the 0 address.");
        bondManager = IBondManager(_bondManager);
    }

    /// @notice Mint multiple fNFT Bonds.
    /// @param _account Account receiving the fNFT bonds.
    /// @param levelID Bond level hex ID.
    /// @param _amount Amount of fNFT bonds being minted.
    /// @param _price Price per fNFT bond. Used to calculate shares and debt.
    /// @dev onlyOwner: Function can be called only by BondManager contract.
    function mintBonds(address _account, bytes4 levelID, uint8 _amount, uint256 _price /*onlyOwner*/) external {
        require(address(bondManager) != address(0), "fNFT Bond: BondManager isn't set.");
        require(bondLevels[levelID].active, "A08");
        require(_amount <= 20, "A09");


        //If sellableAmount is 0, the bonds level does not have a capped supply.
        if(bondLevels[levelID].sellableAmount != 0) {
            require(bondLevels[levelID].sellableAmount >= bondsSold[levelID] + _amount);
            bondsSold[levelID] += _amount;
        }
       
        uint16 _weight = bondLevels[levelID].weight;
        uint256 _unweightedShares = _price;
        uint256 _weightedShares = SafeMath.div(SafeMath.mul(_price, _weight), WEIGHT_PRECISION); 
        
        uint256 _shareDebt = SafeMath.div(SafeMath.mul(_unweightedShares, bondManager.accSharesPerUS()), GLOBAL_PRECISION);
        uint256 _rewardDebt = SafeMath.div(SafeMath.mul(_weightedShares, bondManager.accRewardsPerWS()), GLOBAL_PRECISION);
        uint48 timestamp = uint48(block.timestamp);

        for (uint8 i = 0; i < _amount; i++) {
            uint256 _bondID = totalSupply();

            bonds[_bondID] = Bond({
                bondID: _bondID,
                mint: timestamp,
                levelID: levelID,
                weight: _weight,
                earned: 0,
                unweightedShares: _unweightedShares,
                weightedShares: _weightedShares,
                shareDebt: _shareDebt,
                rewardDebt: _rewardDebt
            });

            _safeMint(_account, _bondID);
            emit BondCreated(_bondID, levelID, _account, timestamp, _price);
        }
        
    }

    /// @notice Claim rewards & shares. Used to update bond's data: shares and debt
    /// @param _account Account calling the claim function from bondManager
    /// @param _bondID Unique fNFT Bond uint ID
    /// @param issuedRewards Rewards issued to bond holder. Used to update earned parameter
    /// @param issuedShares Shares issued to bond. Used to calculate new shares and debt amount
    /// @dev onlyOwner: Function can be called only by BondManager contract
    function claim(address _account, uint256 _bondID, uint256 issuedRewards, uint256 issuedShares) external onlyIfExists(_bondID) /*onlyOwner*/ {
        require(address(bondManager) != address(0), "fNFT Bond: BondManager isn't set.");
        require(ownerOf(_bondID) == _account);

        Bond storage bond = bonds[_bondID];

        bond.earned = SafeMath.add(bond.earned, issuedRewards);
        bond.unweightedShares = SafeMath.add(bond.unweightedShares, issuedShares);
        bond.weightedShares = SafeMath.add(
            bond.weightedShares,
            SafeMath.div(
                SafeMath.mul(
                    issuedShares,
                    bonds[_bondID].weight
                ),
                WEIGHT_PRECISION
            )
        );
        bond.shareDebt = SafeMath.div(SafeMath.mul(bond.unweightedShares, bondManager.accSharesPerUS()), GLOBAL_PRECISION);
        bond.rewardDebt = SafeMath.div(SafeMath.mul(bond.weightedShares, bondManager.accRewardsPerWS()), GLOBAL_PRECISION);

        emit Claim(_bondID, _account, issuedShares, issuedRewards);
    }

    /// @notice Set base URI for fNFT Bond contract.
    /// @dev onlyOwner: Function can be called only by BondManager contract.
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _setBaseURI(baseURI_);
    }

    /// @notice Modifier ensuring that a bond with ID: _bondID exists.
    modifier onlyIfExists(uint256 _bondID) {
        require(_exists(_bondID), "A10");
        _;
    }
    
    /// @notice Returns an array of all hex IDs of active Bond levels
    function getActiveBondLevels() external view returns (bytes4[] memory) {
        return activeBondLevels;
    }

    /// @notice Returns Bond level
    function getBondLevel(bytes4 _levelID) external view returns (BondLevel memory) {
       return bondLevels[_levelID];
    }

    /// @notice Returns bond at _bondID
    function getBond(uint256 _bondID) external view onlyIfExists(_bondID) returns (Bond memory bond) {
        bond = bonds[_bondID];
    }  

    /// @notice Get array of all bonds owned by user. 
    function getBondsIDsOf(address _account) external view returns (uint256[] memory) {
        uint256 _balance = balanceOf(_account);
        uint256[] memory IDs = new uint256[](_balance);
        for (uint256 i = 0; i < _balance; i++) {
            IDs[i] = (tokenOfOwnerByIndex(_account, i));
        }

        return IDs;
    }

    /// @notice Get token URI
    /// @dev Each bond level differes in URI image, thus the tokenURI is generated by appending the baseURI to the hex levelID.
    function tokenURI(uint256 _bondID)
        public
        view
        virtual
        override
        onlyIfExists(_bondID)
        returns (string memory)
    {
        string memory base = baseURI();

        return base;
    }
    
    /// @dev Used to parse bytes4 levelID to string in order to generate tokenURI. 
    function iToHex(bytes memory buffer) internal pure returns (string memory) {
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    /// @notice See {IERC721-safeTransferFrom}.
    /// @dev Overridden to reset Bond earned value.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        Bond storage _bond = bonds[tokenId];
        _bond.earned = 0;

        _safeTransfer(from, to, tokenId, _data);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        Bond storage _bond = bonds[tokenId];
        _bond.earned = 0;

        _safeTransfer(from, to, tokenId, "");
    }

    /// @notice See {IERC721-transferFrom}.
    /// @dev Overridden to reset Bond earned value.
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        Bond storage _bond = bonds[tokenId];
        _bond.earned = 0;

        _transfer(from, to, tokenId);
    }
}
