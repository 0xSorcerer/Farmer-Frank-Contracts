// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IBondManager.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IJoeROuter02.sol";
import "./interfaces/IBoostedMasterChefJoe.sol";
import "./interfaces/IJoePair.sol";
import "./other/Ownable.sol";

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
    }
    
    IBoostedMasterChefJoe public constant BMCJ = IBoostedMasterChefJoe(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IVeJoeStaking public constant VeJoeStaking = IVeJoeStaking(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IStableJoeStaking public constant SJoeStaking = IStableJoeStaking(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IJoeRouter02 public constant TraderJoeRouter = IJoeRouter02(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IERC20 public constant JOE = IERC20(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IBondManager public BondManager;

    address private constant teamAddress = 0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7;
    address private constant investorAddress = 0x1Bf56B7C132B5cC920236AE629C8A93d9E7831e7;
    uint256 private constant FEE_PRECISION = 100_000;
    uint256 private teamFee;
    uint256 private investorFee;
    uint256 bondedTokens;
    uint256 revenue;
    uint256 currentRevenue;

    uint256 DISTRIBUTE_THRESHOLD = 5_000 * 10 ** 18; 

    uint256[] activePIDs;
    mapping(uint256 => bool) isPIDActive;
    
    Strategy public strategy;

    constructor(address _bondManager) {
        setBondManager(_bondManager);
        setTeamFee(2000);
        setInvestorFee(1000);
    }

    /// @notice Change the bond manager address.
    /// @param _bondManager New BondManager address.
    function setBondManager(address _bondManager) public onlyOwner {
        BondManager = IBondManager(_bondManager);
    }

    /// @notice Change the team fee.
    /// @param _fee New fee.
    /// @dev Out of 100_000 (FEE_PRECISION)
    function setTeamFee(uint256 _fee) public onlyOwner {
        teamFee = _fee;
    }

    /// @notice Change the investor fee.
    /// @param _fee New fee.
    /// @dev Out of 100_000 (FEE_PRECISION)
    function setInvestorFee(uint256 _fee) public onlyOwner() {
        investorFee = _fee;
    }

    /// @notice Change minimum amount of revenue required to call the distribute() function.
    /// @param _threshold New threshold.
    function setDistributionThreshold(uint256 _threshold) external onlyOwner {
        DISTRIBUTE_THRESHOLD = _threshold;
    }

    /// @notice Set the Treasury's strategy.
    /// @param _DISTRIBUTION_BONDED_JOE 2 value array storing 1. proportion of BONDED JOE staked to sJOE 2. proportion staked to veJOE
    /// @param _DISTRIBUTION_REINVESTMENTS 3 value array storing 1. proportion of REINVESTED REVENUE staked to sJOE 2. proportion staked to veJOE 3. proportion farmed in BMCJ
    /// @param _PROPORTION_REINVESTMENTS Proportion of REVENUE reinvested within the protocol.
    /// @param _LIQUIDITY_POOL Liquidity pool currently farmed on BMCJ 
    function setStrategy(uint16[2] memory _DISTRIBUTION_BONDED_JOE, uint16[3] memory _DISTRIBUTION_REINVESTMENTS, uint16 _PROPORTION_REINVESTMENTS, address _LIQUIDITY_POOL) public onlyOwner {
        require(_DISTRIBUTION_BONDED_JOE.length == 2);
        require(_DISTRIBUTION_BONDED_JOE[0] + _DISTRIBUTION_BONDED_JOE[1] == 100_000);
        strategy.DISTRIBUTION_BONDED_JOE = _DISTRIBUTION_BONDED_JOE;

        require(_DISTRIBUTION_REINVESTMENTS.length == 3);
        require(_DISTRIBUTION_REINVESTMENTS[0] + _DISTRIBUTION_REINVESTMENTS[1] + _DISTRIBUTION_REINVESTMENTS[2] == 100_000);
        strategy.DISTRIBUTION_REINVESTMENTS = _DISTRIBUTION_REINVESTMENTS;

        require(_PROPORTION_REINVESTMENTS <= 100_000);
        strategy.PROPORTION_REINVESTMENTS = _PROPORTION_REINVESTMENTS;

        strategy.LIQUIDITY_POOL = _LIQUIDITY_POOL;
    }

    /// @notice Distribute revenue to BondManager (where bond holders can later claim them).
    /// @dev Anyone can call this function, if the current revenue is above a certain threshold (DISTRIBUTE_THRESHOLD). 
    function distribute() external {
        harvest();
        require(currentRevenue >= DISTRIBUTE_THRESHOLD);

        uint256 _currentRevenue = currentRevenue;
        uint256 _teamRewards = _currentRevenue * teamFee / FEE_PRECISION;
        uint256 _investorRewards = _currentRevenue * investorFee / FEE_PRECISION;

        JOE.safeTransferFrom(address(this), teamAddress, _teamRewards);
        JOE.safeTransferFrom(address(this), investorAddress, _investorRewards);

        _currentRevenue = SafeMath.sub(_currentRevenue, SafeMath.add(_teamRewards, _investorRewards));

        uint256 _reinvestedAmount = _currentRevenue * strategy.PROPORTION_REINVESTMENTS / 100_000;
        uint256 _rewardedAmount = _currentRevenue - _reinvestedAmount;

        _reinvest(_reinvestedAmount);

        JOE.approve(address(BondManager), _rewardedAmount);
        BondManager.depositRewards(_rewardedAmount, _reinvestedAmount);

        _currentRevenue = 0;
    }

    /// @notice Internal function used to reinvest part of revenue when calling distribute().
    /// @param _amount Amount of JOE tokens to reinvest.
    function _reinvest(uint256 _amount) private {
        uint256[] memory amounts = proportionDivide(_amount, strategy.DISTRIBUTION_REINVESTMENTS);

        JOE.approve(address(SJoeStaking), amounts[0]);
        JOE.approve(address(VeJoeStaking), amounts[0]);

        SJoeStaking.deposit(amounts[0]);
        VeJoeStaking.deposit(amounts[1]);
        _addAndFarmLiquidity(amounts[2], strategy.LIQUIDITY_POOL);
    }

    /// @notice Function called by BondManager contract everytime a bond is minted.
    /// @param _amount Amount of tokens deposited to the treasury,
    function bondDeposit(uint256 _amount) external {
        address _sender = _msgSender();
        require(_sender == address(BondManager));

        JOE.safeTransferFrom(_sender, address(this), _amount);
        bondedTokens += _amount;

        uint256[] memory amounts = proportionDivide(_amount, strategy.DISTRIBUTION_BONDED_JOE);

        JOE.approve(address(SJoeStaking), amounts[0]);
        JOE.approve(address(VeJoeStaking), amounts[1]);
        SJoeStaking.deposit(amounts[0]);
        VeJoeStaking.deposit(amounts[1]);
    }

    /// @notice Convert treasury JOE to LP tokens and farm them on BMCJ.
    /// @param _amount Amount of JOE tokens to farm.
    /// @param _pool Boosted pool address.
    function _addAndFarmLiquidity(uint256 _amount, address _pool) private {
        IJoePair pair = IJoePair(_pool);

        address token0 = pair.token0();
        address token1 = pair.token1();

        address[] memory path = new address[](2);
        path[0] = address(JOE);

        uint256 minAmountOut;
        uint256 amountOutA;

        if (token0 != address(JOE)) {
            JOE.approve(address(TraderJoeRouter), (_amount/2));
            path[1] = token0;
            minAmountOut = ((TraderJoeRouter.getAmountsOut((_amount / 2), path)[1] * 95) / 100);
            amountOutA = (TraderJoeRouter.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
        } else {
            amountOutA = _amount / 2;
        }

        uint256 amountOutB;

        if (token1 != address(JOE)) {
            JOE.approve(address(TraderJoeRouter), (_amount/2));
            path[1] = token1;
            minAmountOut = ((TraderJoeRouter.getAmountsOut((_amount / 2), path)[1] * 95) / 100);
            amountOutB = (TraderJoeRouter.swapExactTokensForTokens((_amount / 2), minAmountOut, path, address(this), (block.timestamp + 1000)))[1];
        } else {
            amountOutB = _amount / 2;
        }

        IERC20(token0).approve(address(TraderJoeRouter), amountOutA);
        IERC20(token1).approve(address(TraderJoeRouter), amountOutB);

        (, , uint256 liquidity) = TraderJoeRouter.addLiquidity(token0, token1, amountOutA, amountOutB, ((amountOutA * 95) / 100), ((amountOutB * 95) / 100), address(this), block.timestamp + 1000);

        uint256 pid = getPoolIDFromLPToken(_pool);

        if (!isPIDActive[pid]) {
            activePIDs.push(pid);
            isPIDActive[pid] = true;
        }

        IERC20(_pool).approve(address(BMCJ), liquidity);

        BMCJ.deposit(pid, liquidity);
    }

    /// @notice External onlyOwner implementation of _addAndFarmLiquidity.
    /// @param _amount Amount of JOE tokens to farm.
    /// @param _pool Boosted pool address.
    function addAndFarmLiquidity(uint256 _amount, address _pool) external onlyOwner {
        _addAndFarmLiquidity(_amount, _pool);
    }

    /// @notice Remove liquidity from Boosted pool and convert assets to JOE.
    /// @param _amount Amount of LP tokens to remove from liquidity.
    /// @param _pool Boosted pool address.
    function removeLiquidity(uint256 _amount, address _pool) external onlyOwner {
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

        harvestPool(pid);

        BMCJ.withdraw(pid, _amount);

        //SAFETY SLIPPAGE
        (uint256 amountA, uint256 amountB) = TraderJoeRouter.removeLiquidity(pair.token0(), pair.token1(), _amount, 0, 0, address(this), block.timestamp);

        address[] memory path = new address[](2);
        path[1] = address(JOE);

        if (pair.token0() != address(JOE)) {
            IERC20(pair.token0()).approve(address(TraderJoeRouter), amountA);
            path[0] = pair.token0();
            TraderJoeRouter.swapExactTokensForTokens(amountA, (amountA * 95) / 100, path, address(this), (block.timestamp + 1000));
        }

        if (pair.token1() != address(JOE)) {
            IERC20(pair.token1()).approve(address(TraderJoeRouter), amountB);
            path[0] = pair.token1();
            TraderJoeRouter.swapExactTokensForTokens(amountB, (amountB * 95) / 100, path, address(this), (block.timestamp + 1000));
        }
    }

    /// @notice Get PID from LP token address.
    /// @param _token LP token address. 
    function getPoolIDFromLPToken(address _token) internal view returns (uint256) {
        for (uint256 i = 0; i < BMCJ.poolLength(); i++) {
            (address _lp, , , , , , , , ) = BMCJ.poolInfo(i);
            if (_lp == _token) {
                return i;
            }
        }
        revert();
    }

    /// @notice Harvest rewards from sJOE and BMCJ farms
    /// @dev Anyone can call this function
    function harvest() public {
        for(uint i = 0; i < activePIDs.length; i++) {
            harvestPool(activePIDs[i]);
        }
        harvestJoe();
    }
 
    /// @notice Harvest rewards from boosted pool.
    /// @param _pid Pool PID. 
    function harvestPool(uint256 _pid) private {
        uint256 balanceBefore = JOE.balanceOf(address(this));
        BMCJ.deposit(_pid, 0);
        uint256 _revenue = JOE.balanceOf(address(this)) - balanceBefore;

        revenue += _revenue;
        currentRevenue += _revenue;
    }

    /// @notice Harvest rewards from sJOE and harvest veJOE. 
    function harvestJoe() private {
        uint256 balanceBefore = JOE.balanceOf(address(this));
        IStableJoeStaking(SJoeStaking).withdraw(0);
        uint256 _revenue = JOE.balanceOf(address(this)) - balanceBefore;

        revenue += _revenue;
        currentRevenue += _revenue; 

        IVeJoeStaking(VeJoeStaking).claim();
    }

    /// @notice Internal function to divide an amount into different proportions.
    /// @param amount_ Amount to divide.
    /// @param _proportions Array of the different proportions in which to divide amount_
    function proportionDivide(uint256 amount_, uint16[] memory _proportions) private pure returns (uint256[] memory _amounts) {
        uint256 amountTotal;
        uint256 proportionTotal;
        _amounts = new uint256[](_proportions.length);

        for (uint256 i = 0; i < _proportions.length; i++) {
            uint256 _amount = (amount_ * _proportions[i]) / 10000;
            amountTotal += _amount;
            proportionTotal += _proportions[i];
            _amounts[i] = _amount;
        }

        require(proportionTotal == 10000);

        require(amountTotal <= amount_);

        if (amountTotal < amount_) {
            _amounts[0] += (amount_ - amountTotal);
        }

        return _amounts;
    }

    function execute(address target, uint256 value, bytes calldata data) external onlyOwner returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        return (success, result);
    }

}
