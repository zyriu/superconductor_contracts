// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/LK99.sol";
import "../src/Master.sol";

contract MasterTest is Test {

    address owner;
    address constant user = address(0x420);
    address constant lpToken = address(0x696969);

    uint256 INITIAL_LK99_SUPPLY = 2_000_000 * 1e18;
    uint256 INITIALIZED_LK99_SUPPLY = 98_000_000 * 1e18;
    uint256 BLOCKS_PER_DAY = 43_200;
    uint256 startBlock;

    Master master;
    LK99 lk99;

    address constant router = 0x9EC6317f261554E7C2995cc6dADcc8CB155A7470;
    address constant WETH = 0x3A4875D2bDC5E4C89C7F8E632ce0D1f9709a4914;

    string BASE_GOERLI_RPC = vm.envString("BASE_GOERLI_RPC");

    function setUp() public {
        vm.selectFork(vm.createFork(BASE_GOERLI_RPC));
        owner = address(this);

        startBlock = block.number + BLOCKS_PER_DAY;
        lk99 = new LK99(INITIAL_LK99_SUPPLY);

        master = new Master(lk99, startBlock);
        vm.warp(block.timestamp + 2 weeks);
        lk99.initializeEmissions(startBlock, INITIALIZED_LK99_SUPPLY);
        lk99.initializeMasterAddress(address(master));
    }

    function testAdd() public {
        master.add(IFaction(0x123));
        vm.expectRevert();
        master.add(IFaction(0x123));
        assertEq(master.factionsLength(), 1);
        (address factionAddress, uint256 lastRewardBlock, uint256 reserve, uint256 factionEmissionRate) =
            master.getFactionInfo(address(0x123));
        assertEq(address(0x123), factionAddress);
        assertEq(lastRewardBlock, startBlock);
        assertEq(reserve, 0);
        assertEq(factionEmissionRate, master.emissionRate());
    }

    function testClaimMasterRewards(uint256 numberOfBlocks) public {
        vm.assume(numberOfBlocks <= BLOCKS_PER_DAY * 21);
        vm.expectRevert("LK99: caller is not the master");
        lk99.claimMasterRewards(1);
        vm.roll(startBlock + numberOfBlocks);
        uint256 newEmissions = 0;
        uint256 blocksProcessed = 0;
        for (uint256 k = 0; k < numberOfBlocks / BLOCKS_PER_DAY + 1; k++) {
            uint256 blocksToProcess = Math.min(BLOCKS_PER_DAY, numberOfBlocks - blocksProcessed);
            newEmissions += (lk99.blockRewardsPerDay(k + 1) * blocksToProcess / BLOCKS_PER_DAY) * 1e18;
            blocksProcessed += blocksToProcess;
        }
        vm.prank(address(master));
        lk99.claimMasterRewards(newEmissions);
        assertEq(lk99.balanceOf(address(master)), newEmissions);
    }

    function testEmissionsOver() public {
        assertEq(lk99.emissionsOver(), false);
        vm.roll(startBlock + BLOCKS_PER_DAY * 3);
        assertEq(lk99.emissionsOver(), false);
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        assertEq(lk99.emissionsOver(), true);
    }

    function testEmitAllocationsFuzz(uint256 numberOfBlocks) public {
        vm.assume(numberOfBlocks <= BLOCKS_PER_DAY * 1000);
        uint256 currentSupply = lk99.totalSupply();
        lk99.emitAllocations();
        assertEq(currentSupply, lk99.totalSupply());
        vm.roll(startBlock);
        lk99.emitAllocations();
        assertEq(currentSupply, lk99.totalSupply());
        vm.roll(startBlock + numberOfBlocks);
        uint256 newEmissions = 0;
        uint256 blocksProcessed = 0;
        for (uint256 k = 0; k < numberOfBlocks / BLOCKS_PER_DAY + 1; k++) {
            uint256 blocksToProcess = Math.min(BLOCKS_PER_DAY, numberOfBlocks - blocksProcessed);
            newEmissions += (lk99.blockRewardsPerDay(k + 1) * blocksToProcess / BLOCKS_PER_DAY) * 1e18;
            blocksProcessed += blocksToProcess;
        }
        assertEq(lk99.emitAllocations(), newEmissions);
    }

    function testEmitAllocationsSet() public {
        uint256 currentSupply = lk99.totalSupply();
        lk99.emitAllocations();
        assertEq(currentSupply, lk99.totalSupply());
        vm.roll(startBlock);
        lk99.emitAllocations();
        assertEq(currentSupply, lk99.totalSupply());
        vm.roll(startBlock + BLOCKS_PER_DAY);
        uint256 newEmissions = lk99.blockRewardsPerDay(1) * 1e18;
        assertEq(lk99.emitAllocations(), newEmissions);
        currentSupply += newEmissions;
        assertEq(lk99.totalSupply(), currentSupply);
        vm.roll(startBlock + BLOCKS_PER_DAY * 3);
        newEmissions = (lk99.blockRewardsPerDay(2) + lk99.blockRewardsPerDay(3)) * 1e18;
        currentSupply += newEmissions;
        assertEq(lk99.emitAllocations(), newEmissions);
        assertEq(lk99.totalSupply(), currentSupply);
        vm.roll(startBlock + BLOCKS_PER_DAY * 3 + 15_000);
        newEmissions = (lk99.blockRewardsPerDay(4) * 15_000 / BLOCKS_PER_DAY) * 1e18;
        currentSupply += newEmissions;
        assertEq(lk99.emitAllocations(), newEmissions);
        assertEq(lk99.totalSupply(), currentSupply);
        vm.roll(startBlock + BLOCKS_PER_DAY * 3 + 30_000);
        newEmissions = (lk99.blockRewardsPerDay(4) * 15_000 / BLOCKS_PER_DAY) * 1e18;
        currentSupply += newEmissions;
        assertEq(lk99.emitAllocations(), newEmissions);
        assertEq(lk99.totalSupply(), currentSupply);
        vm.roll(startBlock + BLOCKS_PER_DAY * 4 + 1500);
        newEmissions = (lk99.blockRewardsPerDay(4) * (BLOCKS_PER_DAY - 30_000) / BLOCKS_PER_DAY + lk99.blockRewardsPerDay(5) * 1500 / BLOCKS_PER_DAY) * 1e18;
        currentSupply += newEmissions;
        assertEq(lk99.emitAllocations(), newEmissions);
        assertEq(lk99.totalSupply(), currentSupply);
        lk99.emitAllocations();
        vm.roll(startBlock + BLOCKS_PER_DAY * 5 + 6000);
        newEmissions = (lk99.blockRewardsPerDay(5) * (BLOCKS_PER_DAY - 1500) / BLOCKS_PER_DAY + lk99.blockRewardsPerDay(6) * 6000 / BLOCKS_PER_DAY) * 1e18;
        currentSupply += newEmissions;
        assertEq(lk99.emitAllocations(), newEmissions);
        assertEq(lk99.totalSupply(), currentSupply);
    }
}
