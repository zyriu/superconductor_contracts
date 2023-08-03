// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/FactionFactory.sol";
import "../src/LK99.sol";
import "../src/Master.sol";
import "../src/interfaces/ISuperconductor.sol";

contract FactionFactoryTest is Test {

    address owner;

    uint256 constant INITIAL_LK99_SUPPLY = 2_000_000 * 1e18;
    uint256 constant INITIALIZED_LK99_SUPPLY = 98_000_000 * 1e18;
    uint256 constant BLOCKS_PER_DAY = 43_200;
    uint256 startBlock;

    Master master;
    FactionFactory factionFactory;
    LK99 lk99;

    address constant router = 0x9EC6317f261554E7C2995cc6dADcc8CB155A7470;
    address constant WETH = 0x3A4875D2bDC5E4C89C7F8E632ce0D1f9709a4914;

    string BASE_GOERLI_RPC = vm.envString("BASE_GOERLI_RPC");

    function setUp() public {
        vm.selectFork(vm.createFork(BASE_GOERLI_RPC));
        owner = address(this);

        startBlock = block.number + BLOCKS_PER_DAY;
        lk99 = new LK99(INITIAL_LK99_SUPPLY);

        vm.warp(block.timestamp + 2 weeks);
        lk99.initializeEmissions(startBlock, INITIALIZED_LK99_SUPPLY);
        master = new Master(lk99, startBlock);
        lk99.initializeMasterAddress(address(master));
        factionFactory = new FactionFactory(lk99, master, address(0x42), 0);
    }

    function testCreateFaction() public {
        address lpToken = address(0x69696969);

        vm.expectRevert();
        vm.prank(address(0x420420));
        factionFactory.createFaction(lpToken);

        factionFactory.createFaction(lpToken);
        factionFactory.createFaction(lpToken);
        factionFactory.createFaction(lpToken);
        factionFactory.createFaction(lpToken);
        vm.expectRevert();
        factionFactory.createFaction(lpToken);
    }

    function testIsFaction() public {
        address lpToken = address(0x69696969);
        address faction = factionFactory.createFaction(lpToken);
        assertEq(factionFactory.isFaction(address(faction)), true);
        assertEq(factionFactory.isFaction(address(0x666)), false);
    }
}
