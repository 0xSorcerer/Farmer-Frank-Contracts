// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./other/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IJoeROuter02.sol";
import "./interfaces/IBoostedMasterChefJoe.sol";
import "./interfaces/IJoePair.sol";


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
    address JoeRouter;
    address baseToken;

    IBoostedMasterChefJoe boostedMC = IBoostedMasterChefJoe(0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7);

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

    function claim() external {
        IStableJoeStaking(SJoeStaing).withdraw(0);
        IVeJoeStaking(VeJoeStaking).claim();

        //Liquidity claim
    }

    function addAndFarmLiquidity(uint256 _amount, address _pool) public onlyOwner {
        IJoePair pair = IJoePair(_pool);
        IJoeRouter02 router = IJoeRouter02(JoeRouter);

        IERC20(baseToken).approve(JoeRouter, 999999999999999999999999999999);

        address token0 = pair.token0();
        address token1 = pair.token1();

        address[] memory path = new address[](2);
        path[0] = baseToken;

        uint256 minAmountOut;
        uint256 amountOutA;

        if(token0 != baseToken) {
            path[1] = token0;
            minAmountOut = (router.getAmountsOut((_amount / 2), path)[1] * 95 / 100);
            amountOutA = (router.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
            IERC20(token0).approve(JoeRouter, 999999999999999999999999999999);
        } else {
            amountOutA = _amount / 2;
        }

        uint256 amountOutB;

        if(token1 != baseToken) {
            path[1] = token1;
            minAmountOut = (router.getAmountsOut((_amount / 2), path)[1] * 95 / 100);
            amountOutB = (router.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
            IERC20(token1).approve(JoeRouter, 999999999999999999999999999999);
        } else {
            amountOutB = _amount / 2;
        }

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(token0, token1, amountOutA, amountOutB, (amountOutA * 95 / 100), (amountOutB * 95 / 100), address(this), block.timestamp + 1000);

        uint256 pid = getPoolIDFromLPToken(_pool);

        IERC20(_pool).approve(address(boostedMC), 999999999999999999999999999999);

        boostedMC.deposit(pid, liquidity);
    }

    function getPoolIDFromLPToken(address _token) public view returns (uint256) {
        for(uint256 i = 0; i < boostedMC.poolLength(); i++) {
            (address _lp, , , , , , , , ) = boostedMC.poolInfo(i);
            if(_lp == _token) {
                return i;
            }
        }
        revert();
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