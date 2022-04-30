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

/*
contract RevenueSplitter {
    using SafeMath for uint256;

    uint256 internal _totalPriorityShares = 0;
    uint256 internal _totalShares = 0;

    mapping(address => uint256) internal _priorityShares;
    mapping(address => uint256) internal _shares;

    address[] internal _priorityReceivers;
    address[] internal _receivers;

    uint256 private constant PERCENTAGE_PRECISION = 10**5;

    function _addReceiver(address _account, uint256 shares_, bool _priority) internal {
        require(shares_ > 0);
        if (_priority) {
            _priorityShares[_account] == 0 ? _priorityReceivers.push(_account) : ();
            _totalPriorityShares = SafeMath.add(_totalPriorityShares, shares_);
            _priorityShares[_account] = SafeMath.add(_priorityShares[_account], shares_);
        } else {
            _shares[_account] == 0 ? _receivers.push(_account) : ();
            _totalShares = SafeMath.add(_totalShares, shares_);
            _shares[_account] = SafeMath.add(_shares[_account], shares_);
        }
    }
    
    function _removeReceiver(address _account, bool _priority) internal {
        if (_priority) {
            require(_priorityShares[_account] > 0);

            _priorityShares[_account] = 0;

            bool found = false;
            for (uint256 i = 0; i < _priorityReceivers.length; i++) {
                if (found) {
                    _priorityReceivers[i - 1] = _priorityReceivers[i];
                }

                if (_priorityReceivers[i] == _account) {
                    found = true;
                }
            }
            _priorityReceivers.pop();
        } else {
            require(_shares[_account] > 0);

            _shares[_account] = 0;

            bool found = false;
            for (uint256 i = 0; i < _receivers.length; i++) {
                if (found) {
                    _receivers[i - 1] = _receivers[i];
                }

                if (_receivers[i] == _account) {
                    found = true;
                }
            }
            _receivers.pop();
        }
    }

    function _changeReceiverShares(address _account, uint256 shares_, bool _priority) internal {
        require(shares_ > 0);
        _priority ? require(_priorityShares[_account] > 0) : require(_shares[_account] > 0);
        _priority ? _priorityShares[_account] = shares_ : _shares[_account] = shares_;
    }
}
*/

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

    IBoostedMasterChefJoe boostedMC =
        IBoostedMasterChefJoe(0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7);

    uint256 bondedTokens;

    uint256[] activePIDs;
    mapping(uint256 => bool) isPIDActive;

    uint256 revenue;
    uint256 currentRevenue;

    address private constant teamAddress = 0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7;
    address private constant investorAddress = 0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7;
    
    uint256 private teamFee;
    uint256 private investorFee; 
    uint256 private FEE_PRECISION = 100_000;

    IBondManager public bondManager;

    Strategy public strategy;

    constructor(address _bondManager) {
        bondManager = IBondManager(_bondManager);

        setTeamFee(2000);
        setInvestorFee(1000);
    }

    function reinvest(uint256 _amount) private onlyOwner {
        uint256[] memory amounts = proportionDivide(_amount, strategy.DISTRIBUTION_REINVESTMENTS);

        IStableJoeStaking(SJoeStaing).deposit(amounts[0]);
        IVeJoeStaking(VeJoeStaking).deposit(amounts[1]);
        addAndFarmLiquidity(amounts[2], strategy.LIQUIDITY_POOL);
    }

    function distribute() external onlyOwner {
        uint256 _currentRevenue = currentRevenue;
        uint256 _teamRewards = _currentRevenue * teamFee / FEE_PRECISION;
        uint256 _investorRewards = _currentRevenue * investorFee / FEE_PRECISION;

        IERC20(baseToken).transferFrom(address(this), teamAddress, _teamRewards);
        IERC20(baseToken).transferFrom(address(this), investorAddress, _investorRewards);

        _currentRevenue = SafeMath.sub(_currentRevenue, SafeMath.add(_teamRewards, _investorRewards));

        uint256 _reinvestedAmount = _currentRevenue * strategy.PROPORTION_REINVESTMENTS / 100_000;
        uint256 _rewardedAmount = _currentRevenue - _reinvestedAmount;

        reinvest(_reinvestedAmount);

        IERC20(baseToken).approve(address(bondManager), _rewardedAmount);
        bondManager.depositRewards(_rewardedAmount, _reinvestedAmount);
    }

    function setTeamFee(uint256 _fee) public onlyOwner {
        teamFee = _fee;
    }

    function setInvestorFee(uint256 _fee) public onlyOwner() {
        investorFee = _fee;
    }

    function setStrategy(
        uint16[2] memory _DISTRIBUTION_BONDED_JOE,
        uint16[3] memory _DISTRIBUTION_REINVESTMENTS,
        uint16 _PROPORTION_REINVESTMENTS,
        address _LIQUIDITY_POOL,
        uint256 _LIQUIDITY_POOL_ID
    ) public onlyOwner {
        require(_DISTRIBUTION_BONDED_JOE.length == 2);
        require(_DISTRIBUTION_BONDED_JOE[0] + _DISTRIBUTION_BONDED_JOE[1] == 100_000);
        strategy.DISTRIBUTION_BONDED_JOE = _DISTRIBUTION_BONDED_JOE;

        require(_DISTRIBUTION_REINVESTMENTS.length == 3);
        require(_DISTRIBUTION_REINVESTMENTS[0] + _DISTRIBUTION_REINVESTMENTS[1] + _DISTRIBUTION_REINVESTMENTS[2] == 100_000);
        strategy.DISTRIBUTION_REINVESTMENTS = _DISTRIBUTION_REINVESTMENTS;

        require(_PROPORTION_REINVESTMENTS <= 100_000);
        strategy.PROPORTION_REINVESTMENTS = _PROPORTION_REINVESTMENTS;

        strategy.LIQUIDITY_POOL = _LIQUIDITY_POOL;
        strategy.LIQUIDITY_POOL_ID = _LIQUIDITY_POOL_ID;
    }

    function bondDeposit(uint256 _amount) external /*Only for bond manager*/ {
        address _sender = _msgSender();

        IERC20(baseToken).safeTransferFrom(_sender, address(this), _amount);
        bondedTokens += _amount;

        uint256[] memory amounts = proportionDivide(_amount, strategy.DISTRIBUTION_BONDED_JOE);

        IStableJoeStaking(SJoeStaing).deposit(amounts[0]);
        IVeJoeStaking(VeJoeStaking).deposit(amounts[1]);
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

        if (token0 != baseToken) {
            path[1] = token0;
            minAmountOut = ((router.getAmountsOut((_amount / 2), path)[1] * 95) / 100);
            amountOutA = (router.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
            IERC20(token0).approve(JoeRouter, 999999999999999999999999999999);
        } else {
            amountOutA = _amount / 2;
        }

        uint256 amountOutB;

        if (token1 != baseToken) {
            path[1] = token1;
            minAmountOut = ((router.getAmountsOut((_amount / 2), path)[1] * 95) / 100);
            amountOutB = (router.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
            IERC20(token1).approve(JoeRouter, 999999999999999999999999999999);
        } else {
            amountOutB = _amount / 2;
        }

        (, , uint256 liquidity) = router.addLiquidity(token0, token1, amountOutA, amountOutB, ((amountOutA * 95) / 100), ((amountOutB * 95) / 100), address(this), block.timestamp + 1000);

        uint256 pid = getPoolIDFromLPToken(_pool);

        if (!isPIDActive[pid]) {
            activePIDs.push(pid);
            isPIDActive[pid] = true;
        }

        IERC20(_pool).approve(address(boostedMC), 999999999999999999999999999999);

        boostedMC.deposit(pid, liquidity);
    }

    function removeLiquidity(uint256 _amount, address _pool) public onlyOwner {
        uint256 liquidityBalance = IERC20(_pool).balanceOf(address(this));
        require(liquidityBalance >= _amount);

        uint256 pid = getPoolIDFromLPToken(_pool);

        if (_amount == liquidityBalance) {
            isPIDActive[pid] = false;
            bool isPIDFound = false;

            for (uint256 i = 0; i < activePIDs.length; i++) {
                if (isPIDFound) {
                    activePIDs[i - i] = activePIDs[i];
                }
                if (activePIDs[i] == pid) {
                    isPIDFound = true;
                }
            }

            activePIDs.pop();
        }

        IJoePair pair = IJoePair(_pool);
        IJoeRouter02 router = IJoeRouter02(JoeRouter);

        harvestPool(pid);

        boostedMC.withdraw(pid, _amount);

        //SAFETY SLIPPAGE
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(pair.token0(), pair.token1(), _amount, 0, 0, address(this), block.timestamp);

        address[] memory path = new address[](2);
        path[1] = baseToken;

        if (pair.token0() != baseToken) {
            path[0] = pair.token0();
            router.swapExactTokensForTokens(amountA, (amountA * 95) / 100, path, address(this), (block.timestamp + 1000));
        }

        if (pair.token1() != baseToken) {
            path[0] = pair.token1();
            router.swapExactTokensForTokens(amountB, (amountB * 95) / 100, path, address(this), (block.timestamp + 1000));
        }
    }

    function getPoolIDFromLPToken(address _token)
        public
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < boostedMC.poolLength(); i++) {
            (address _lp, , , , , , , , ) = boostedMC.poolInfo(i);
            if (_lp == _token) {
                return i;
            }
        }
        revert();
    }

    function harvestPool(uint256 _pid) public {
        uint256 revenueBefore = IERC20(baseToken).balanceOf(address(this));
        boostedMC.deposit(_pid, 0);
        revenue = IERC20(baseToken).balanceOf(address(this)) - revenueBefore;
    }

    function harvestJoe() external {
        uint256 revenueBefore = IERC20(baseToken).balanceOf(address(this));
        IStableJoeStaking(SJoeStaing).withdraw(0);
        revenue = IERC20(baseToken).balanceOf(address(this)) - revenueBefore;
        IVeJoeStaking(VeJoeStaking).claim();
    }

    function proportionDivide(uint256 amount, uint16[] memory proportions)
        internal
        pure
        returns (uint256[] memory amounts)
    {
        uint256 amountTotal;
        uint256 proportionTotal;
        amounts = new uint256[](proportions.length);

        for (uint256 i = 0; i < proportions.length; i++) {
            uint256 _amount = (amount * proportions[i]) / 10000;
            amountTotal += _amount;
            proportionTotal += proportions[i];
            amounts[i] = _amount;
        }

        require(proportionTotal == 10000);

        require(amountTotal <= amount);

        if (amountTotal < amount) {
            amounts[0] += (amount - amountTotal);
        }

        return amounts;
    }
}
