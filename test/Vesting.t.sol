// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "./utils/ERC20Mintable.sol";
import "../src/LK99.sol";
import "../src/Vesting.sol";


contract VestingTest is Test {

  address owner;

  uint256 INITIAL_LK99_SUPPLY = 100_000_000 * 1e18;
  uint256 TOTAL_VESTING_AMOUNT = 30_000_000 * 1e18;
  uint256 BLOCKS_PER_DAY = 43_200;
  uint256 startBlock;

  LK99 lk99;
  Vesting vesting;

  function setUp() public {
    owner = address(this);

    startBlock = block.number + BLOCKS_PER_DAY * 7;
    lk99 = new LK99(INITIAL_LK99_SUPPLY);
    vesting = new Vesting(address(lk99));
    lk99.excludeFromBurn(address(vesting), true);

    assertEq(vesting.initialized(), false);
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(address(0x42));
    vesting.initializeVesting(startBlock);
    lk99.approve(address(vesting), UINT256_MAX);
    vesting.initializeVesting(startBlock);
    assertEq(vesting.initialized(), true);
    assertEq(lk99.balanceOf(address(vesting)), TOTAL_VESTING_AMOUNT);
    assertEq(lk99.balanceOf(owner), 70_000_000 * 1e18);
    lk99.transfer(address(0xdead), 70_000_000 * 1e18);
  }

  function testClaim() public {
    assertEq(lk99.balanceOf(owner), 0);
    (uint256 totalAmount, uint256 vestedAmount, uint256 lastClaimBlock,) = vesting.vesters(owner);
    assertEq(totalAmount, 10_000_000 * 1e18);
    assertEq(vestedAmount, 0);
    assertEq(lastClaimBlock, startBlock);
    vm.roll(startBlock + BLOCKS_PER_DAY);
    vesting.claim();
    (totalAmount, vestedAmount, lastClaimBlock,) = vesting.vesters(owner);
    uint256 claimedAmount = totalAmount / 21;
    assertEq(lk99.balanceOf(owner), claimedAmount);
    assertEq(vestedAmount, claimedAmount);
    assertEq(lastClaimBlock, block.number);
    vm.roll(startBlock + BLOCKS_PER_DAY * 21 + 1);
    vesting.claim();
    (totalAmount, vestedAmount, lastClaimBlock,) = vesting.vesters(owner);
    assertEq(lk99.balanceOf(owner), totalAmount);
    assertEq(vestedAmount, totalAmount);
    assertEq(lastClaimBlock, block.number);
  }

  function testClaimUnauthorized() public {
    vm.roll(startBlock + BLOCKS_PER_DAY * 21);
    vm.prank(address(0x42));
    vm.expectRevert();
    vesting.claim();
  }

  function testSlash() public {
    assertEq(lk99.balanceOf(owner), 0);
    (uint256 totalAmount, uint256 vestedAmount, uint256 lastClaimBlock,) = vesting.vesters(owner);
    vm.roll(startBlock + BLOCKS_PER_DAY);
    vesting.claim();
    (totalAmount, vestedAmount, lastClaimBlock,) = vesting.vesters(owner);
    uint256 claimedAmount = totalAmount / 21;
    assertEq(lk99.balanceOf(owner), claimedAmount);
    assertEq(vestedAmount, claimedAmount);
    assertEq(lastClaimBlock, block.number);
    vesting.slash(address(0x1));
    vm.expectRevert("nothing to claim");
    vm.prank(address(0x1));
    vesting.claim();
    vm.roll(startBlock + BLOCKS_PER_DAY * 21 + 1);
    vesting.claim();
    (totalAmount, vestedAmount, lastClaimBlock,) = vesting.vesters(owner);
    assertEq(totalAmount, 20_000_000 * 1e18);
    assertEq(lk99.balanceOf(owner), totalAmount);
    assertEq(vestedAmount, totalAmount);
    assertEq(lastClaimBlock, block.number);
  }
}
