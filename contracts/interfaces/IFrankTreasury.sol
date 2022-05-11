interface IFrankTreasury {

    struct Strategy {
        uint256[] DISTRIBUTION_BONDED_JOE; 
        uint256[] DISTRIBUTION_REINVESTMENTS;
        uint256 PROPORTION_REINVESTMENTS;
        address LIQUIDITY_POOL;
    }

    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function BondManager() external view returns (address);

    function JOE() external view returns (address);

    function SJoeStaking() external view returns (address);

    function TraderJoeRouter() external view returns (address);

    function VeJoeStaking() external view returns (address);

    function getCurrentRevenue() external view returns (uint256);

    function getTotalRevenue() external view returns (uint256);

    function getStrategy() external view returns (Strategy memory);

    function setBondManager(address bondManager) external;

    function setFee(uint256 fee) external;

    function setDistributionThreshold(uint256 threshold) external;

    function setSlippage (uint256 _slippage) external;

    function setStrategy(uint256[2] memory DISTRIBUTION_BONDED_JOE, uint256[3] memory DISTRIBUTION_REINVESTMENTS, uint256 PROPORTION_REINVESTMENTS, address LIQUIDITY_POOL) external;

    function distribute() external;

    function bondDeposit(uint256 amount, address user) external;

    function addAndFarmLiquidity(uint256 amount, address pool) external;

    function removeLiquidity(uint256 amount, address pool) external;

    function reallocateLiquidity(address previousPool, address newPool, uint256 amount) external;

    function harvestAll() external;

    function withdraw(address token, uint256 amount, address receiver) external;

    function execute(address target, uint256 value, bytes calldata data) external returns (bool, bytes memory);
}