// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "forge-std/Test.sol";
import "../src/LK99.sol";
import "../src/Master.sol";

contract LK99Test is Test {

    address owner;
    address constant user = address(0x420);

    uint256 constant INITIAL_LK99_SUPPLY = 2_000_000 * 1e18;
    uint256 constant INITIALIZED_LK99_SUPPLY = 98_000_000 * 1e18;
    uint256 constant TOTAL_LK99_EMISSION = 100_000_000 * 1e18;
    uint256 constant BLOCKS_PER_DAY = 43_200;
    uint256 startBlock;

    Master master;
    LK99 lk99;

    address constant router = 0x9EC6317f261554E7C2995cc6dADcc8CB155A7470;
    address constant WETH = 0x3A4875D2bDC5E4C89C7F8E632ce0D1f9709a4914;

    string BASE_GOERLI_RPC = vm.envString("BASE_GOERLI_RPC");

    function setUp() public {
        vm.selectFork(vm.createFork(BASE_GOERLI_RPC));
        owner = address(this);

        startBlock = block.number + BLOCKS_PER_DAY * 7;
        lk99 = new LK99(INITIAL_LK99_SUPPLY);
    }

    function testBlockRewardsPerDay() public {
        assertEq(lk99.blockRewardsPerDay(1), 3_500_000);
        assertEq(lk99.blockRewardsPerDay(2), 3_700_000);
        assertEq(lk99.blockRewardsPerDay(5), 4_000_000);
        assertEq(lk99.blockRewardsPerDay(10), 4_500_000);
        assertEq(lk99.blockRewardsPerDay(21), 5_600_000);
        assertEq(lk99.blockRewardsPerDay(22), 0);
        uint256 total;
        for (uint256 k = 0; k < 22; k++) {
            total += lk99.blockRewardsPerDay(k);
        }
        assertEq(total, TOTAL_LK99_EMISSION / 1e18);
    }

    function testBurn(uint256 amount) public {
        vm.assume(amount <= INITIAL_LK99_SUPPLY);
        lk99.burn(amount);
        assertEq(lk99.balanceOf(owner), INITIAL_LK99_SUPPLY - amount);
    }

    function testConstructor() public {
        assertEq(lk99.balanceOf(owner), INITIAL_LK99_SUPPLY);
    }

    function testCurrentDayBeforeInitialized(uint256 numberOfDays) public {
        vm.assume(numberOfDays < 200);
        for (uint256 k = 0; k < numberOfDays; k++) {
            vm.roll(startBlock + k * BLOCKS_PER_DAY);
            assertEq(lk99.currentDay(), 0);
        }
    }

    function testCurrentDayWhenInitialized(uint256 numberOfDays) public {
        vm.warp(block.timestamp + 2 weeks);
        lk99.initializeEmissions(startBlock, INITIALIZED_LK99_SUPPLY);
        vm.assume(numberOfDays < 200);
        vm.roll(startBlock - 1);
        assertEq(lk99.currentDay(), 0);
        vm.roll(startBlock);
        assertEq(lk99.currentDay(), 1);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        assertEq(lk99.currentDay(), 2);
        vm.roll(startBlock + BLOCKS_PER_DAY * numberOfDays);
        assertEq(lk99.currentDay(), numberOfDays + 1);
    }

    function testSuperconductorCapacityBeforeInitialized() public {
        for (uint256 k = 0; k < 22; k++) {
            vm.roll(startBlock + BLOCKS_PER_DAY * k);
            assertEq(lk99.superconductorCapacity(), 0);
        }
    }

    function testSuperconductorCapacityWhenInitialized() public {
        vm.warp(block.timestamp + 2 weeks);
        lk99.initializeEmissions(startBlock, INITIALIZED_LK99_SUPPLY);
        for (uint256 k = 0; k < 22; k++) {
            vm.roll(startBlock + BLOCKS_PER_DAY * k);
            assertEq(lk99.currentDay(), k + 1);
            assertEq(lk99.superconductorCapacity(), (k + 1) * 45 + 10);
        }
        vm.roll(startBlock + BLOCKS_PER_DAY * 20);
        assertEq(lk99.superconductorCapacity(), 955);
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        assertEq(lk99.superconductorCapacity(), 1000);
    }
}
