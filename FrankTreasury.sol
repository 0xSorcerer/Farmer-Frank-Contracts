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

/// @title Farmer Frank Treasury.
/// @author @0xSorcerer

contract FrankTreasury is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Strategy information.
    struct Strategy {
        // 2 element array containing proportions (total = 100_000) dictating how bonded JOE will be utilized.
        //      DISTRIBUTION_BONDED_JOE[0] = Proportion of JOE staked to sJOE.
        //      DISTRIBUTION_BONDED_JOE[1] = Proportion of JOE staked to veJOE.
        uint256[] DISTRIBUTION_BONDED_JOE; 
        // 3 element array containing proportions (total = 100_000) dictating how reinvested revenue will be utilized.
        //      DISTRIBUTION_REINVESTMENTS[0] = Proportion of JOE staked to sJOE.
        //      DISTRIBUTION_REINVESTMENTS[1] = Proportion of JOE staked to veJOE.
        //      DISTRIBUTION_REINVESTMENTS[2] = Proportion of JOE farmed in liquidity.
        uint256[] DISTRIBUTION_REINVESTMENTS;
        // Proportion (total = 100_000) of revenue reinvested within the protocol.
        uint256 PROPORTION_REINVESTMENTS;
        // Liquidity pool to farm. 
        address LIQUIDITY_POOL;
    }

    /// @notice Contract interfaces
    IBoostedMasterChefJoe public constant BMCJ = IBoostedMasterChefJoe(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);
    IVeJoeStaking public constant VeJoeStaking = IVeJoeStaking(0x25D85E17dD9e544F6E9F8D44F99602dbF5a97341);
    IStableJoeStaking public constant SJoeStaking = IStableJoeStaking(0x1a731B2299E22FbAC282E7094EdA41046343Cb51);
    IJoeRouter02 public constant TraderJoeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    IERC20 public constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    IERC20 public constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IBondManager public BondManager;

    address private constant teamAddress = 0xE6461Da23098d2420Ce9A35b329FA82db0919c30;
    address private constant investorAddress = 0xE6461Da23098d2420Ce9A35b329FA82db0919c30;
    
    uint256 private constant FEE_PRECISION = 100_000;
    uint256 private internalFee;

    /// @dev Revenue that gets distributed when calling distribute().
    uint256 private currentRevenue;
    /// @dev Total revenue that has been distributed through distribute().
    uint256 private totalRevenue;

    /// @dev Minimum amount of currentRevenue required to distribute rewards.
    uint256 private DISTRIBUTE_THRESHOLD = 5_000 * 10 ** 18; 

    /// @dev Storing BMCJ pools utilized Treasury is farming in.
    uint256[] private activePIDs;
    mapping(uint256 => bool) private isPIDActive;

    /// @dev Slippage amount used when swapping tokens.
    uint256 private slippage = 960;
    
    /// @dev Strategy object.
    Strategy private strategy;

    event SET_FEE (uint256 fee);

    event SET_DISTRIBUTION_THRESHOLD (uint256 threshold);

    event SET_SLIPPAGE (uint256 slippage);

    event SET_STRATEGY (uint256[2] DISTRIBUTION_BONDED_JOE, uint256[3] DISTRIBUTION_REINVESTMENTS, uint256 PROPORTION_REINVESTMENTS, address LIQUIDITY_POOL);

    event ADD_LIQUIDITY (address indexed pool, uint256 amount);

    event REMOVE_LIQUIDITY (address indexed pool, uint256 amount);

    constructor() {
        setFee(2000);
        setStrategy([uint256(50000),50000], [uint256(45000),45000,10000], 50000, 0x706b4f0Bf3252E946cACD30FAD779d4aa27080c0);
    }

    function getCurrentRevenue() public view returns (uint256) {
        return currentRevenue;
    }

    function getTotalRevenue() public view returns (uint256) {
        return totalRevenue;
    }

    function getStrategy() public view returns (Strategy memory) {
        return strategy;
    }

    /// @notice Change the bond manager address.
    /// @param bondManager New BondManager address.
    function setBondManager(address bondManager) external onlyOwner {
        BondManager = IBondManager(bondManager);
    }

    /// @notice Change the fee for team and investors.
    /// @param fee New fee.
    /// @dev Team and investors will have the same fee.
    function setFee(uint256 fee) public onlyOwner {
        internalFee = fee;

        emit SET_FEE(fee);
    }

    /// @notice Change minimum amount of revenue required to call the distribute() function.
    /// @param threshold New threshold.
    function setDistributionThreshold(uint256 threshold) external onlyOwner {
        DISTRIBUTE_THRESHOLD = threshold;

        emit SET_DISTRIBUTION_THRESHOLD(threshold);
    }

    /// @notice Change slippage variable.
    /// @param _slippage New slippage amount.
    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;

        emit SET_SLIPPAGE(slippage);
    }

    /// @notice Set the Treasury's strategy.
    /// @param DISTRIBUTION_BONDED_JOE 2 value array storing 1. proportion of BONDED JOE staked to sJOE 2. proportion staked to veJOE.
    /// @param DISTRIBUTION_REINVESTMENTS 3 value array storing 1. proportion of REINVESTED REVENUE staked to sJOE 2. proportion staked to veJOE 3. proportion farmed in BMCJ.
    /// @param PROPORTION_REINVESTMENTS Proportion of REVENUE reinvested within the protocol.
    /// @param LIQUIDITY_POOL Liquidity pool currently farmed on BMCJ.
    function setStrategy(uint256[2] memory DISTRIBUTION_BONDED_JOE, uint256[3] memory DISTRIBUTION_REINVESTMENTS, uint256 PROPORTION_REINVESTMENTS, address LIQUIDITY_POOL) public onlyOwner {
        require(DISTRIBUTION_BONDED_JOE.length == 2);
        require(DISTRIBUTION_BONDED_JOE[0] + DISTRIBUTION_BONDED_JOE[1] == 100_000);
        strategy.DISTRIBUTION_BONDED_JOE = DISTRIBUTION_BONDED_JOE;

        require(DISTRIBUTION_REINVESTMENTS.length == 3);
        require(DISTRIBUTION_REINVESTMENTS[0] + DISTRIBUTION_REINVESTMENTS[1] + DISTRIBUTION_REINVESTMENTS[2] == 100_000);
        strategy.DISTRIBUTION_REINVESTMENTS = DISTRIBUTION_REINVESTMENTS;

        require(PROPORTION_REINVESTMENTS <= 100_000);
        strategy.PROPORTION_REINVESTMENTS = PROPORTION_REINVESTMENTS;

        strategy.LIQUIDITY_POOL = LIQUIDITY_POOL;

        emit SET_STRATEGY(DISTRIBUTION_BONDED_JOE, DISTRIBUTION_REINVESTMENTS, PROPORTION_REINVESTMENTS, LIQUIDITY_POOL);
    }

    /// @notice Distribute revenue to BondManager (where bond holders can later claim rewards and shares).
    /// @dev Anyone can call this function, if the current revenue is above a certain threshold (DISTRIBUTE_THRESHOLD). 
    function distribute() external {
        harvestAll();
        require(currentRevenue >= DISTRIBUTE_THRESHOLD, "Revenue can't be distributed yet.");

        uint256 _currentRevenue = currentRevenue;
        uint256 feeAmount = SafeMath.div(SafeMath.mul(_currentRevenue, internalFee), FEE_PRECISION);

        JOE.safeTransfer(teamAddress, feeAmount);
        JOE.safeTransfer(investorAddress, feeAmount);

        _currentRevenue = SafeMath.sub(_currentRevenue, SafeMath.mul(feeAmount, 2));

        uint256 reinvestedAmount = SafeMath.div(SafeMath.mul(_currentRevenue, strategy.PROPORTION_REINVESTMENTS), 100_000);
        uint256 rewardedAmount = SafeMath.sub(_currentRevenue, reinvestedAmount);

        reinvest(reinvestedAmount);

        JOE.approve(address(BondManager), rewardedAmount);
        BondManager.depositRewards(rewardedAmount, reinvestedAmount);

        totalRevenue = SafeMath.add(totalRevenue, currentRevenue);
        currentRevenue = 0;
    }

    /// @notice Internal function used to reinvest part of revenue when calling distribute().
    /// @param amount Amount of JOE tokens to reinvest.
    function reinvest(uint256 amount) private {
        uint256[] memory amounts = proportionDivide(amount, strategy.DISTRIBUTION_REINVESTMENTS);

        uint256 excess = _addAndFarmLiquidity(amounts[2], strategy.LIQUIDITY_POOL);

        JOE.approve(address(SJoeStaking), amounts[0] + excess);
        JOE.approve(address(VeJoeStaking), amounts[1]);

        SJoeStaking.deposit(amounts[0] + excess);
        VeJoeStaking.deposit(amounts[1]);
    }

    /// @notice Function called by BondManager contract everytime a bond is minted.
    /// @param amount Amount of tokens deposited to the treasury.
    /// @param user Address of bond minter.
    function bondDeposit(uint256 amount, address user) external {
        require(_msgSender() == address(BondManager));

        JOE.safeTransferFrom(user, address(this), amount);

        uint256[] memory amounts = proportionDivide(amount, strategy.DISTRIBUTION_BONDED_JOE);
        
        JOE.approve(address(SJoeStaking), amounts[0]);
        JOE.approve(address(VeJoeStaking), amounts[1]);

        SJoeStaking.deposit(amounts[0]);
        VeJoeStaking.deposit(amounts[1]);
    }


    /// @notice Convert treasury JOE to LP tokens and farms them on BMCJ.
    /// @param amount Amount of JOE tokens to farm.
    /// @param pool Boosted pool address.
    /// @dev Only JOE pools are supported, in order to keep partial exposure to the JOE token. 
    function _addAndFarmLiquidity(uint256 amount, address pool) private returns (uint256 excess) {
        IJoePair pair = IJoePair(pool);

        require(pair.token0() == address(JOE) || pair.token1() == address(JOE));

        address otherToken = pair.token0() == address(JOE) ? pair.token1() : pair.token0();

        uint256 safeAmount = (amount / 2 * slippage) / 1000;

        address[] memory path = new address[](2);
        path[0] = address(JOE);
        path[1] = otherToken;

        JOE.approve(address(TraderJoeRouter), safeAmount);

        uint256 amountOutOther = TraderJoeRouter.swapExactTokensForTokens(safeAmount, (TraderJoeRouter.getAmountsOut(safeAmount, path)[1]) * slippage / 1000, path, address(this), block.timestamp + 2000)[1];

        (uint256 reserveJOE, uint256 reserveOther,) = pair.getReserves();

        if(pair.token1() == address(JOE)) {
            (reserveJOE, reserveOther) = (reserveOther, reserveJOE);
        }

        uint quoteJOE = TraderJoeRouter.quote(amountOutOther, reserveOther, reserveJOE);

        JOE.approve(address(TraderJoeRouter), quoteJOE);
        IERC20(otherToken).approve(address(TraderJoeRouter), amountOutOther);

        (, uint256 amountInJoe, uint256 liquidity) = TraderJoeRouter.addLiquidity(otherToken, address(JOE), amountOutOther, quoteJOE, 0, 0, address(this), block.timestamp + 1000);

        require(amountInJoe + safeAmount <= amount, "Try setting higher slippage.");

        if(amountInJoe + safeAmount < amount) {
            excess = amount - (amountInJoe + safeAmount);
        } else {
            excess = 0;
        }

        

        uint256 pid = getPoolIDFromLPToken(pool);

        if (!isPIDActive[pid]) {
            activePIDs.push(pid);
            isPIDActive[pid] = true;
        }

        IERC20(pool).approve(address(BMCJ), liquidity);
        
        uint256 balanceBefore = JOE.balanceOf(address(this));
        BMCJ.deposit(pid, liquidity);
        currentRevenue += (JOE.balanceOf(address(this)) - balanceBefore); 

        

        emit ADD_LIQUIDITY(pool, liquidity);
    }

    /// @notice Remove liquidity from Boosted pool and convert assets to JOE.
    /// @param amount Amount of LP tokens to remove from liquidity.
    /// @param pool Boosted pool address.
    function _removeLiquidity(uint256 amount, address pool) private returns (uint256) {
        uint256 liquidityBalance = IERC20(pool).balanceOf(address(this));
        require(liquidityBalance >= amount);

        
        uint256 pid = getPoolIDFromLPToken(pool);

        if (amount == liquidityBalance) {
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
        
        

        IJoePair pair = IJoePair(pool);

        address otherToken = pair.token0() == address(JOE) ? pair.token1() : pair.token0();

        
        uint256 balanceBefore = JOE.balanceOf(address(this));
        BMCJ.withdraw(pid, amount);
        uint256 balanceAfter = JOE.balanceOf(address(this));
        currentRevenue +=  balanceAfter - balanceBefore;

        IERC20(pool).approve(address(TraderJoeRouter), amount);

        (uint256 amountOther, ) = TraderJoeRouter.removeLiquidity(otherToken, address(JOE), amount, 0, 0, address(this), block.timestamp);

        address[] memory path = new address[](2);
        path[0] = otherToken;
        path[1] = address(JOE);

        IERC20(otherToken).approve(address(TraderJoeRouter), amountOther);
        TraderJoeRouter.swapExactTokensForTokens(amountOther, (TraderJoeRouter.getAmountsOut(amountOther, path)[1]) * slippage / 1000, path, address(this), (block.timestamp + 1000));

        emit ADD_LIQUIDITY(pool, amount);

        return 0;
    }

    /// @notice Public onlyOwner implementation of _addAndFarmLiquidity function.
    /// @param amount Amount of JOE tokens to farm.
    /// @param pool Boosted pool address.
    /// @dev Used to reallocate protocol owned liquidity. First liquidity from a pool is removed with removeLiquidity() and then it is migrated to another pool
    /// through this function. 
    function addAndFarmLiquidity(uint256 amount, address pool) public onlyOwner returns (uint256 excess) {
        excess = _addAndFarmLiquidity(amount, pool);
    }

    /// @notice Public onlyOwner implementation of _removeLiquidity function.
    /// @param amount Amount of LP tokens to remove.
    /// @param pool Boosted pool address.
    function removeLiquidity(uint256 amount, address pool) public onlyOwner returns (uint256) {
        return _removeLiquidity(amount, pool);
    }

    /// @notice Function used to migrate liquidity from one pool to another.
    /// @param previousPool Pool from which liquidity must be removed.
    /// @param newPool Pool from which liquidity must be added.
    /// @param amount Amount of LP (_previousPool) tokens that must be migrated.
    function reallocateLiquidity(address previousPool, address newPool, uint256 amount) external onlyOwner {
        uint256 JOEAmount = _removeLiquidity(amount, previousPool);
        uint256 excess = _addAndFarmLiquidity(JOEAmount, newPool);

        JOE.approve(address(SJoeStaking), excess);
        SJoeStaking.deposit(excess);
    }

    /// @notice Harvest rewards from sJOE, BMCJ farms and claim veJOE tokens.
    /// @dev Anyone can call this function
    function harvestAll() public { 
        uint256 balanceBefore = JOE.balanceOf(address(this));
        
        
        for(uint i = 0; i < activePIDs.length; i++) {
            BMCJ.deposit(activePIDs[i], 0);
        }
        
        
        claimJoeFromStaking();
        currentRevenue += (JOE.balanceOf(address(this)) - balanceBefore); 
    }

    /// @notice claims rewards from sJOE and claims veJOE. 
    function claimJoeFromStaking() private {
        IStableJoeStaking(SJoeStaking).withdraw(0);

        // Converts USDC rewards to JOE

        
        
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(JOE);

        uint256 USDCBalance = USDC.balanceOf(address(this));

        USDC.approve(address(TraderJoeRouter), USDCBalance);
        TraderJoeRouter.swapExactTokensForTokens(USDCBalance, (TraderJoeRouter.getAmountsOut(USDCBalance, path)[1]) * slippage / 1000, path, address(this), (block.timestamp + 1000));
        
        

        IVeJoeStaking(VeJoeStaking).claim();
    }

    /// @notice Internal function to divide an amount into different proportions.
    /// @param amount Amount to divide.
    /// @param proportions Array of the different proportions in which to divide amount_
    function proportionDivide(uint256 amount, uint256[] memory proportions) private pure returns (uint256[] memory amounts) {
        uint256 amountTotal;
        uint256 proportionTotal;
        amounts = new uint256[](proportions.length);

        for (uint256 i = 0; i < proportions.length; i++) {
            uint256 _amount = (amount * proportions[i]) / 100_000;
            amountTotal += _amount;
            proportionTotal += proportions[i];
            amounts[i] = _amount;
        }

        require(proportionTotal == 100_000);
        require(amountTotal <= amount);

        // If there is a small excess due _amount not being perfectly divisible by the proportions, that excess is
        // added to the first amount -> Always (sJOE) in this case.
        if (amountTotal < amount) {
            amounts[0] += (amount - amountTotal);
        }

        return amounts;
    }

    /// @notice Get PID from LP token address.
    /// @param token LP token address. 
    function getPoolIDFromLPToken(address token) internal view returns (uint256) {
        for (uint256 i = 0; i < BMCJ.poolLength(); i++) {
            (address _lp, , , , , , , , ) = BMCJ.poolInfo(i);
            if (_lp == token) {
                return i;
            }
        }
        revert();
    }
    

    /// @notice Emergency withdraw function.
    /// @param token Token to withdraw.
    /// @param receiver Token receiver.
    function withdraw(address token, uint256 amount, address receiver) external onlyOwner {
        IERC20(token).transfer(receiver, amount);
    }

    /// @notice Open-ended execute function.
    function execute(address target, uint256 value, bytes calldata data) external onlyOwner returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        return (success, result);
    }

}
