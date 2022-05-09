// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/ERC721.sol";
import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";

/*
    TODO: 
        TREASURY: Convert sJOE rewards to JOE
        MANAGER: Add whitelist merkle tree
        MANAGER/BOND: Fix URI. 
*/

/// @title ERC721 implementation for Farmer Frank NFT Bonds (Perpetuities). 
/// @author @0xSorcerer

/// @notice Users are not supposed to interract with this contract. Most functions are marked
/// as onlyOwner, where the contract owner will be a BondManager contract. Users will use the BondManager
/// contract to mint and claim, which will call the functions in this contract.
/// This contract holds Bond Data and Bond Level data. 

contract fNFTBond is ERC721, Ownable {

    using SafeMath for uint256;
    using Address for address;

    /// @notice Info of each fNFT Bond.
    struct Bond {
        // Unique fNFT Bond ID.
        uint256 bondID;
        // Mint timestamp.
        uint48 mint;
        // Unique fNFT Bond level hex ID.
        bytes4 levelID;
        // Amount of REWARDS (not shares) earned historically when holding bond. Resets on transfer.
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

    /// @notice Bond manager interface used to get accSharesPerUS() and accRewardsPerWS().
    IBondManager public bondManager;

    /// @dev Precision constants
    uint256 private constant GLOBAL_PRECISION = 10**18;
    uint256 private constant WEIGHT_PRECISION = 100;

    /// @dev Maximum amount of Bond levels the bond can support.
    uint16 private constant MAX_BOND_LEVELS = 10;

    /// @dev Mapping storing all bonds data.
    mapping(uint256 => Bond) private bonds; 
    /// @dev Array storing all active bonds level: bonds that can be minted. 
    /// @dev Mapping to store how many bonds were minted per level. Used only for bonds with maximum supply.
    mapping(bytes4 => uint256) private bondsSold;
    /// @notice Amount of currently active Bond levels
    /// @dev Must be <= MAX_BOND_LEVELS

    event NewBondLevel (
        bytes4 indexed levelID,
        uint256 price,
        uint16 weight,
        string name
    );

    event BondLevelChanged (
        bytes4 indexed levelID,
        uint256 price,
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
        uint48 mint
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
    }

    /// @notice Connect fNFTBond contract (this) to its manager. Manager is needed to get accSharesPerUS() and accRewardsPerWS().
    function _linkBondManager(address _bondManager) external onlyOwner {
        require(_bondManager != address(0), "fNFT Bond: Bond manager can't be set to the 0 address.");
        bondManager = IBondManager(_bondManager);
    }

    function mintBonds(address _account, bytes4 levelID, uint8 _amount, uint256 _weightedShares, uint256 _unweightedShares) onlyOwner external {
        require(address(bondManager) != address(0), "fNFT Bond: BondManager isn't set.");

        //uint256 _weightedShares = SafeMath.div(SafeMath.mul(getBondLevel(levelID).price, _weight), WEIGHT_PRECISION); 
        
        uint256 _shareDebt = SafeMath.div(SafeMath.mul(_unweightedShares, bondManager.accSharesPerUS()), GLOBAL_PRECISION);
        uint256 _rewardDebt = SafeMath.div(SafeMath.mul(_weightedShares, bondManager.accRewardsPerWS()), GLOBAL_PRECISION);
        uint48 timestamp = uint48(block.timestamp);

        for (uint8 i = 0; i < _amount; i++) {
            uint256 _bondID = totalSupply();

            bonds[_bondID] = Bond({
                bondID: _bondID,
                mint: timestamp,
                levelID: levelID,
                earned: 0,
                unweightedShares: _unweightedShares,
                weightedShares: _weightedShares,
                shareDebt: _shareDebt,
                rewardDebt: _rewardDebt
            });

            _safeMint(_account, _bondID);
            emit BondCreated(_bondID, levelID, _account, timestamp);
        }
        
    }

    /// @notice Claim rewards & shares. Used to update bond's data.
    /// @param _account Account calling the claim function from bondManager.
    /// @param _bondID Unique fNFT Bond uint ID.
    /// @param issuedRewards Rewards issued to bond holder. Used to update earned parameter.
    /// @param issuedShares Shares issued to bond. Used to calculate new shares amount.
    function claim(address _account, uint256 _bondID, uint256 issuedRewards, uint256 issuedShares) external onlyIfExists(_bondID) {
        require(address(bondManager) != address(0), "fNFT Bond: BondManager isn't set.");
        require(ownerOf(_bondID) == _account);

        Bond memory _bond = bonds[_bondID];

        _bond.earned = SafeMath.add(_bond.earned, issuedRewards);
        _bond.unweightedShares = SafeMath.add(_bond.unweightedShares, issuedShares);
        _bond.weightedShares = SafeMath.add(
            _bond.weightedShares,
            SafeMath.div(
                SafeMath.mul(
                    issuedShares,
                    bondManager.getBondLevel(bonds[_bondID].levelID).weight
                ),
                WEIGHT_PRECISION
            )
        );
        _bond.shareDebt = SafeMath.div(SafeMath.mul(_bond.unweightedShares, bondManager.accSharesPerUS()), GLOBAL_PRECISION);
        _bond.rewardDebt = SafeMath.div(SafeMath.mul(_bond.weightedShares, bondManager.accRewardsPerWS()), GLOBAL_PRECISION);

        bonds[_bondID] = _bond;

        emit Claim(_bondID, _account, issuedShares, issuedRewards);
    }

    /// @notice Set base URI for fNFT Bond contract.
    /// @param baseURI_ New base URI.
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _setBaseURI(baseURI_);
    }

    /// @notice Modifier ensuring that a bond with ID: _bondID exists.
    /// @notice Unique fNFT Bond ID. 
    modifier onlyIfExists(uint256 _bondID) {
        require(_exists(_bondID), "A10");
        _;
    }
    
    /// @notice Returns bond at _bondID.
    /// @notice Unique fNFT Bond ID. 
    function getBond(uint256 _bondID) external view onlyIfExists(_bondID) returns (Bond memory bond) {
        bond = bonds[_bondID];
    }  

    /// @notice Get array of all bonds owned by user. 
    /// @param _account Account whose Bonds' IDs will be returned.
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

    /// @dev See {IERC721-safeTransferFrom}.
    /// @dev Overridden to reset Bond earned value.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            bondManager.setUserXP(bondManager.getUserXP(from) - bondManager.getBondLevel(bonds[tokenId].levelID).price, from);
        }

        _safeTransfer(from, to, tokenId, _data);
    }

    /// @dev See {IERC721-safeTransferFrom}.
    /// @dev Overridden to reset Bond earned value.
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            bondManager.setUserXP(bondManager.getUserXP(from) - bondManager.getBondLevel(bonds[tokenId].levelID).price, from);
        }

        _safeTransfer(from, to, tokenId, "");
    }

    /// @notice See {IERC721-transferFrom}.
    /// @dev Overridden to reset Bond earned value.
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            bondManager.setUserXP(bondManager.getUserXP(from) - bondManager.getBondLevel(bonds[tokenId].levelID).price, from);
        }

        _transfer(from, to, tokenId);
    }
}
