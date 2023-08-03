// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILK99 is IERC20 {
  function burn(uint256 amount) external;
  function claimMasterRewards(uint256 rewards) external returns (uint256 effectiveAmount);
  function currentDay() external view returns (uint256);
  function currentEmissionRate() external view returns (uint256);
  function emissionsOver() external view returns (bool);
  function lastEmission() external view returns (uint256);
  function pendingEmissions(uint256 lastRewardBlock) external view returns (uint256 emissions);
  function superconductorCapacity() external view returns (uint256);
}
