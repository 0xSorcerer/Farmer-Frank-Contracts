// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/ERC721.sol";
import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";

/// @title ERC721 implementation for Farmer Frank NFT Bonds (Perpetuities). 
/// @author @0xSorcerer

/// Users are not supposed to interract with this contract. Most functions are marked
/// as onlyOwner, where the contract owner will be a BondManager contract. Users will use the BondManager
/// contract to mint and claim, which will call the functions in this contract.
/// This contract holds Bond Data.

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

contract fNFTBond is ERC721, Ownable {

    using SafeMath for uint256;
    using Address for address;

    struct Bond {
        uint256 bondID;
        bytes4 levelID;
        uint256 index;
    }

    IBondManager public BondManager;

    uint256 private constant GLOBAL_PRECISION = 10**18;
    uint256 private constant WEIGHT_PRECISION = 100;

    mapping(uint256 => Bond) private bonds; 

    event BOND_CREATED (uint256 indexed bondID, bytes4 indexed levelID, address indexed user, uint256 mint);
    event BOND_UPDATED (uint256 indexed bondID, address indexed user, uint256 newUnweightedShares, uint256 newWeightedShares);

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        
    }

    modifier onlyIfExists(uint256 bondID) {
        require(_exists(bondID), "Bond Manager: Bond ID does not exist.");
        _;
    }

    function getBond(uint256 bondID) external view onlyIfExists(bondID) returns (Bond memory bond) {
        bond = bonds[bondID];
    }  

    function getBondsIDsOf(address user) external view returns (uint256[] memory) {
        uint256 _balance = balanceOf(user);
        uint256[] memory IDs = new uint256[](_balance);
        for (uint256 i = 0; i < _balance; i++) {
            IDs[i] = (tokenOfOwnerByIndex(user, i));
        }

        return IDs;
    }

    function tokenURI(uint256 bondID) public view virtual override onlyIfExists(bondID) returns (string memory) {
        string memory base = baseURI();
        return string(abi.encodePacked(base, "/", iToHex(abi.encodePacked(bonds[bondID].levelID))));
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

    function linkBondManager(address bondManager) external onlyOwner {
        require(bondManager != address(0), "fNFT Bond: Bond manager can't be set to the 0 address.");
        BondManager = IBondManager(bondManager);
    }

    function mintBonds(address user, bytes4 levelID, uint256 index, uint256 amount) onlyOwner external {
        require(address(BondManager) != address(0), "fNFT Bond: BondManager isn't set.");

        for (uint i = 0; i < amount; i++) {
            uint256 bondID = totalSupply();

            bonds[bondID] = Bond({
                bondID: bondID,
                levelID: levelID,
                index: index
            });

            _safeMint(user, bondID);
        }
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _setBaseURI(baseURI);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

    /*
        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            BondManager.setUserXP(BondManager.getUserXP(from) - BondManager.getBondLevel(bonds[tokenId].levelID).price, from);
            BondManager.setUserXP(BondManager.getUserXP(to) + BondManager.getBondLevel(bonds[tokenId].levelID).price, to);
        }
        */

        _safeTransfer(from, to, tokenId, _data);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

/*
        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            BondManager.setUserXP(BondManager.getUserXP(from) - BondManager.getBondLevel(bonds[tokenId].levelID).price, from);
            BondManager.setUserXP(BondManager.getUserXP(to) + BondManager.getBondLevel(bonds[tokenId].levelID).price, to);
        }
        */

        _safeTransfer(from, to, tokenId, "");
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

/*
        if(from != to) {
            Bond storage _bond = bonds[tokenId];
            _bond.earned = 0;
            BondManager.setUserXP(BondManager.getUserXP(from) - BondManager.getBondLevel(bonds[tokenId].levelID).price, from);
            BondManager.setUserXP(BondManager.getUserXP(to) + BondManager.getBondLevel(bonds[tokenId].levelID).price, to);
        }
        */

        _transfer(from, to, tokenId);
    }
}
