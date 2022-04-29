// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";
import "./libraries/SafeERC20.sol";

interface IStableJoeStaking {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}

interface IVeJoeStaking {
    function deposit(uint256 _amount) external;
    function claim() external;
    function withdraw(uint256 _amount) external;
}

contract FrankTreasury is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address SJoeStaing;
    address VeJoeStaking;
    address baseToken;

    uint256 bondedTokens;

    function bondDeposit(uint256 _amount) external /*Only for bond manager*/{
        address _sender = _msgSender();

        IERC20(baseToken).safeTransferFrom(_sender, address(this), _amount);
        bondedTokens += _amount;




    }

    function proportionDivide(uint256 amount, uint16[] memory proportions) internal view returns (uint256[] memory amounts) {
        uint amountTotal;
        uint proportionTotal;
        amounts = new uint256[](proportions.length);
        
        for(uint i = 0; i < proportions.length; i++) {
            uint256 _amount = amount * proportions[i] / 10000;
            amountTotal += _amount; 
            proportionTotal += proportions[i];
            amounts[i] = _amount;
        }

        require(proportionTotal == 10000);

        require(amountTotal <= amount);

        if(amountTotal < amount) {
            amounts[0] += (amount - amountTotal);
        }

        return amounts;
    }

}