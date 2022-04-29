// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IBoostedMasterChefJoe {
  function JOE (  ) external view returns ( address );
  function MASTER_CHEF_V2 (  ) external view returns ( address );
  function MASTER_PID (  ) external view returns ( uint256 );
  function VEJOE (  ) external view returns ( address );
  function add ( uint96 _allocPoint, uint32 _veJoeShareBp, address _lpToken, address _rewarder ) external;
  function claimableJoe ( uint256, address ) external view returns ( uint256 );
  function deposit ( uint256 _pid, uint256 _amount ) external;
  function emergencyWithdraw ( uint256 _pid ) external;
  function harvestFromMasterChef (  ) external;
  function init ( address _dummyToken ) external;
  function initialize ( address _MASTER_CHEF_V2, address _joe, address _veJoe, uint256 _MASTER_PID ) external;
  function joePerSec (  ) external view returns ( uint256 amount );
  function massUpdatePools (  ) external;
  function owner (  ) external view returns ( address );
  function pendingTokens ( uint256 _pid, address _user ) external view returns ( uint256 pendingJoe, address bonusTokenAddress, string memory bonusTokenSymbol, uint256 pendingBonusToken );
  function poolInfo ( uint256 ) external view returns ( address lpToken, uint96 allocPoint, uint256 accJoePerShare, uint256 accJoePerFactorPerShare, uint64 lastRewardTimestamp, address rewarder, uint32 veJoeShareBp, uint256 totalFactor, uint256 totalLpSupply );
  function poolLength (  ) external view returns ( uint256 pools );
  function renounceOwnership (  ) external;
  function set ( uint256 _pid, uint96 _allocPoint, uint32 _veJoeShareBp, address _rewarder, bool _overwrite ) external;
  function totalAllocPoint (  ) external view returns ( uint256 );
  function transferOwnership ( address newOwner ) external;
  function updateFactor ( address _user, uint256 _newVeJoeBalance ) external;
  function updatePool ( uint256 _pid ) external;
  function userInfo ( uint256, address ) external view returns ( uint256 amount, uint256 rewardDebt, uint256 factor );
  function withdraw ( uint256 _pid, uint256 _amount ) external;
}
