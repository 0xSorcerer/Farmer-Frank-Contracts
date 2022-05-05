interface IFrankTreasury {
    function BondManager() external view returns (address);
    function JOE() external view returns (address);
    function SJoeStaking() external view returns (address);
    function TraderJoeRouter() external view returns (address);
    function VeJoeStaking() external view returns (address);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function strategy() external view returns ( uint16 PROPORTION_REINVESTMENTS, address LIQUIDITY_POOL);
    function transferOwnership(address newOwner) external;
    function setBondManager(address _bondManager) external;
    function setFee(uint256 _fee) external;
    function setDistributionThreshold(uint256 _threshold) external;
    function setStrategy(uint16[2] memory _DISTRIBUTION_BONDED_JOE, uint16[3] memory _DISTRIBUTION_REINVESTMENTS, uint16 _PROPORTION_REINVESTMENTS, address _LIQUIDITY_POOL) external;
    function distribute() external;
    function bondDeposit(uint256 _amount, address _sender) external;
    function addAndFarmLiquidity(uint256 _amount, address _pool) external;
    function removeLiquidity(uint256 _amount, address _pool) external;
    function harvest() external;
    function execute(address target, uint256 value, bytes calldata data) external returns ( bool, bytes memory );
}