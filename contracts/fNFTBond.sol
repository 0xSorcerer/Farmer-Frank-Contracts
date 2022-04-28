// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/ERC721.sol";
import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";

contract fNFTBond is ERC721, Ownable {

    using SafeMath for uint256;
    using Address for address;

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
        uint16 basePrice;
        uint16 weight;
        string name;
    }

    IBondManager public bondManager;

    uint256 internal constant GLOBAL_PRECISION = 10**18;
    uint256 internal constant WEIGHT_PRECISION = 100;

    uint16 internal constant MAX_BOND_LEVELS = 10;

    mapping(uint256 => Bond) private bonds; 
    mapping(bytes4 => BondLevel) private bondLevels;
    bytes4[] private activeBondLevels;

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

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        _setBaseURI("ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq");

        //Create initial Bond levels
        _addBondLevelAtIndex("Level I", 10, 100, totalActiveBondLevels);
        _addBondLevelAtIndex("Level II", 100, 105, totalActiveBondLevels);
        _addBondLevelAtIndex("Level III", 1000, 110, totalActiveBondLevels);
        _addBondLevelAtIndex("Level IV", 5000, 115, totalActiveBondLevels);
    }

    function linkBondManager(address _bondManager) external onlyOwner {
        bondManager = IBondManager(_bondManager);
    }

    function _addBondLevelAtIndex(string memory _name, uint16 _basePrice, uint16 _weight, uint16 _index) public onlyOwner returns (bytes4) {
        require(!(totalActiveBondLevels >= MAX_BOND_LEVELS), "A01");
        require(_index <= totalActiveBondLevels, "A02");

        bytes4 levelID = bytes4(keccak256(abi.encodePacked(_name, _basePrice, _weight, block.timestamp)));

        BondLevel memory _level = BondLevel({
            levelID: levelID,
            active: true,
            basePrice: _basePrice,
            weight: _weight,
            name: _name
        });

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

    function _changeBondLevel(bytes4 levelID, string memory _name, uint16 _basePrice, uint16 _weight) external onlyOwner {
        bondLevels[levelID] = BondLevel({
            levelID: levelID,
            active: true,
            basePrice: _basePrice,
            weight: _weight,
            name: _name
        });

        emit BondLevelChanged(levelID, _basePrice, _weight, _name);
    }

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

    function mintBonds(address _account, bytes4 levelID, uint8 _amount, uint256 _price /*onlyOwner*/) external {
        require(bondLevels[levelID].active, "A08");
        require(_amount <= 20, "A09");

        uint16 _weight = bondLevels[levelID].weight;
        uint256 _unweightedShares = _price;
        uint256 _weightedShares = (_price * _weight) / WEIGHT_PRECISION;
        uint256 _shareDebt = 0;
        uint256 _rewardDebt = 0;

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

    function claim(address _account, uint256 _bondID, uint256 issuedRewards, uint256 issuedShares) external onlyIfExists(_bondID) /*onlyOwner*/ {
        require(ownerOf(_bondID) == _account);

        Bond storage bond = bonds[_bondID];

        bond.earned = SafeMath.add(bond.earned, issuedRewards);
        bond.unweightedShares = SafeMath.add(bond.unweightedShares, issuedShares);
        bond.weightedShares = SafeMath.add(
            bond.weightedShares,
            SafeMath.div(
                SafeMath.mul(
                    issuedShares,
                    bondLevels[bonds[_bondID].levelID].weight
                ),
                WEIGHT_PRECISION
            )
        );
        bond.shareDebt = SafeMath.div(SafeMath.mul(bond.unweightedShares, bondManager.accSharesPerUS()), GLOBAL_PRECISION);
        bond.rewardDebt = SafeMath.div(SafeMath.mul(bond.weightedShares, bondManager.accRewardsPerWS()), GLOBAL_PRECISION);

        emit Claim(_bondID, _account, issuedShares, issuedRewards);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _setBaseURI(baseURI_);
    }

    modifier onlyIfExists(uint256 _bondID) {
        require(_exists(_bondID), "A10");
        _;
    }
    
    function getActiveBondLevels() external view returns (bytes4[] memory) {
        return activeBondLevels;
    }

    function getBondLevel(bytes4 _levelID) external view returns (BondLevel memory) {
       return bondLevels[_levelID];
    }

    function getBond(uint256 _bondID) external view onlyIfExists(_bondID) returns (Bond memory bond) {
        bond = bonds[_bondID];
    }  

    function getBondsIDsOf(address _account) external view returns (uint256[] memory) {
        uint256 _balance = balanceOf(_account);
        uint256[] memory IDs = new uint256[](_balance);
        for (uint256 i = 0; i < _balance; i++) {
            IDs[i] = (tokenOfOwnerByIndex(_account, i));
        }

        return IDs;
    }

    function tokenURI(uint256 _bondID)
        public
        view
        virtual
        override
        onlyIfExists(_bondID)
        returns (string memory)
    {
        string memory base = baseURI();

        if (bytes(base).length == 0) {
            return "";
        }

        return string(abi.encodePacked(base, "/", iToHex(abi.encodePacked(bonds[_bondID].levelID))));
    }

    function iToHex(bytes memory buffer) internal pure returns (string memory) {
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
