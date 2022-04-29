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

    struct Strategy {
        uint16[] DISTRIBUTION_BONDED_JOE; //
        uint16[] DISTRIBUTION_REINVESTMENTS;
        uint16 PROPORTION_REINVESTMENTS;
        address LIQUIDITY_POOL;
        uint256 LIQUIDITY_POOL_ID;
    }

    address SJoeStaing;
    address VeJoeStaking;
    address baseToken;

    uint256 bondedTokens;

    Strategy public strategy;

    function setStrategy(uint16[2] memory _DISTRIBUTION_BONDED_JOE, uint16[3] memory _DISTRIBUTION_REINVESTMENTS, uint16 _PROPORTION_REINVESTMENTS, address _LIQUIDITY_POOL, uint256 _LIQUIDITY_POOL_ID) public onlyOwner {
        require(_DISTRIBUTION_BONDED_JOE.length == 2);
        require(_DISTRIBUTION_BONDED_JOE[0] + _DISTRIBUTION_BONDED_JOE[1] == 10000);
        strategy.DISTRIBUTION_BONDED_JOE = _DISTRIBUTION_BONDED_JOE;

        require(_DISTRIBUTION_REINVESTMENTS.length == 3);
        require(_DISTRIBUTION_REINVESTMENTS[0] + _DISTRIBUTION_REINVESTMENTS[1] + _DISTRIBUTION_REINVESTMENTS[2] == 10000);
        strategy.DISTRIBUTION_REINVESTMENTS = _DISTRIBUTION_REINVESTMENTS;

        require(_PROPORTION_REINVESTMENTS <= 10000);
        strategy.PROPORTION_REINVESTMENTS = _PROPORTION_REINVESTMENTS;

        strategy.LIQUIDITY_POOL = _LIQUIDITY_POOL;
        strategy.LIQUIDITY_POOL_ID = _LIQUIDITY_POOL_ID;
    }

    function bondDeposit(uint256 _amount) external /*Only for bond manager*/{
        address _sender = _msgSender();

        IERC20(baseToken).safeTransferFrom(_sender, address(this), _amount);
        bondedTokens += _amount;

        uint256[] memory amounts = proportionDivide(_amount, strategy.DISTRIBUTION_BONDED_JOE);

        IStableJoeStaking(SJoeStaing).deposit(amounts[0]);
        IVeJoeStaking(VeJoeStaking).deposit(amounts[1]);
    }



    function proportionDivide(uint256 amount, uint16[] memory proportions) internal pure returns (uint256[] memory amounts) {
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