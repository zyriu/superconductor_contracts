// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IFaction is IERC721 {
  function exists(uint256 tokenId) external view returns (bool);
  function getFactionInfo() external view returns (
    address lpToken,
    address lk99,
    uint256 lastRewardBlock,
    uint256 accRewardsPerShare,
    uint256 lpSupply
  );
  function getStakingPosition(uint256 tokenId) external view returns (
    bool isLocked,
    uint256 amount,
    uint256 amountWithMultiplier,
    uint256 rewardDebt
  );
  function hasDeposits() external view returns (bool);
}
