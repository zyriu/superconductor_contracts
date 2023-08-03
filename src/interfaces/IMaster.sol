// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./ILK99.sol";

interface IMaster {
  function claimRewards() external returns (uint256);
  function getFactionInfo(address factionAddress_) external view returns (
    address factionAddress,
    uint256 lastRewardBlock,
    uint256 reserve,
    uint256 factionEmissionRate
  );
  function lk99() external view returns (ILK99);
  function owner() external view returns (address);
}
