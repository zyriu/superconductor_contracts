// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface ISuperconductor {
  function creditPoints(address member, uint256 points) external;
  function dispatch() external;
  function joinFaction(address user) external;
  function leaveFaction(address user) external;
}
