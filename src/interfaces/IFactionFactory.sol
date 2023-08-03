// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IFactionFactory {
  function factionsAmount() external view returns (uint256);
  function factions(uint256 index) external view returns (address);
  function isFaction(address) external view returns (bool);
  function superconductor() external view returns (address);
}
