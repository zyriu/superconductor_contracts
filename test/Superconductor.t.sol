// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "./utils/ERC20Mintable.sol";
import "../src/FactionFactory.sol";
import "../src/LK99.sol";
import "../src/Master.sol";
import "../src/Superconductor.sol";
import "../src/interfaces/IFactory.sol";


contract SuperconductorTest is Test {

    address owner;
    address pledge = address(0x69420);
    address alice = address(0x69691);
    address bobby = address(0x69692);
    address carie = address(0x69693);
    address danny = address(0x69694);

    IERC20 lpToken;
    Faction factionA;
    Faction factionB;
    Faction factionC;
    Faction factionD;

    uint256 constant INITIAL_LK99_SUPPLY = 2_000_000 * 1e18;
    uint256 constant INITIALIZED_LK99_SUPPLY = 98_000_000 * 1e18;
    uint256 constant BLOCKS_PER_DAY = 43_200;
    uint256 startBlock;

    Master master;
    FactionFactory factionFactory;
    LK99 lk99;
    Superconductor superconductor;

    address constant factory = 0xA224d96AEDFaee784A16F89f8670e419Ee6f70f0;
    address constant router = 0x4aEFd5CCD22496DD60c5b214c8Cf2a122f88A1FD;
    address constant WETH = 0x9C4cC2624E7959A01945faBAC28A9426167076e3;

    string BASE_GOERLI_RPC = vm.envString("BASE_GOERLI_RPC");

    receive() payable external {}

    function setUp() public {
        vm.selectFork(vm.createFork(BASE_GOERLI_RPC));
        owner = address(this);
        startBlock = block.number + BLOCKS_PER_DAY;
        lk99 = new LK99(INITIAL_LK99_SUPPLY);

        master = new Master(lk99, startBlock);
        vm.warp(block.timestamp + 2 weeks);
        lk99.initializeEmissions(startBlock, INITIALIZED_LK99_SUPPLY);
        lk99.initializeMasterAddress(address(master));
        lk99.excludeFromBurn(address(master), true);

        lpToken = IERC20(IFactory(factory).createPair(address(lk99), WETH));
        lk99.approve(router, UINT256_MAX);
        IRouter(router).addLiquidityETH{value: 24 ether}(
            address(lk99),
            10_000_000 * 1e18,
            10_000_000 * 1e18,
            24 ether,
            owner,
            UINT256_MAX
        );

        superconductor = new Superconductor(pledge, router, address(lk99), WETH, address(lpToken));
        factionFactory = new FactionFactory(lk99, master, address(superconductor), 420);
        superconductor.initialize(address(factionFactory));

        factionA = Faction(factionFactory.createFaction(address(lpToken)));
        lk99.excludeFromBurn(address(factionA), true);
        master.add(factionA);
        factionB = Faction(factionFactory.createFaction(address(lpToken)));
        lk99.excludeFromBurn(address(factionB), true);
        master.add(factionB);
        factionC = Faction(factionFactory.createFaction(address(lpToken)));
        lk99.excludeFromBurn(address(factionC), true);
        master.add(factionC);
        factionD = Faction(factionFactory.createFaction(address(lpToken)));
        lk99.excludeFromBurn(address(factionD), true);
        master.add(factionD);
    }

    function testDispatch() public {
        assertEq(address(superconductor).balance, 0);
        assertEq(pledge.balance, 0);
        uint256 totalSupplyBeforeDispatch = lk99.totalSupply();
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        assertLt(lk99.totalSupply(), totalSupplyBeforeDispatch);
        assertGt(address(superconductor).balance, 0);
        assertGt(pledge.balance, 0);
        assertEq(lk99.balanceOf(address(superconductor)), 0);
    }

    function testHarvestPoints() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        uint256 tokenId = factionA.lastTokenId();
        (, uint256 amount, , ) = factionA.getStakingPosition(tokenId);
        vm.roll(startBlock + BLOCKS_PER_DAY * 2);
        (, uint256 points) = superconductor.members(alice);
        assertEq(points, 0);
        factionA.harvestPointsOnly(tokenId);
        assertEq(lk99.balanceOf(alice), 0);
        (, points) = superconductor.members(alice);
        assertApproxEqRel(points, (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4, 1e13);
        factionA.harvestPosition(tokenId);
        assertApproxEqRel(points, (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4, 1e13);
        assertApproxEqRel(
            lk99.balanceOf(alice),
            (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4 * 145 / 1000 * 1e18,
            1e2
        ); // 14.5% on third day
    }

    function testJoinFaction() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance / 2, false);
        (address faction, ) = superconductor.members(alice);
        assertEq(faction, address(factionA));
        assertEq(superconductor.totalFactionPlayers(address(factionA)), 1);
        lpToken.approve(address(factionB), UINT256_MAX);
        uint256 remainingBalance = lpToken.balanceOf(alice);
        vm.expectRevert("user is already in a faction");
        factionB.createPosition(remainingBalance, false);
    }

    function testJoinFactionAfterSuperconductorCharged() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        vm.expectRevert("superconductor is fully charged");
        factionA.createPosition(lpTokenBalance, false);
    }

    function testLeaveFaction() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        assertEq(superconductor.totalFactionPlayers(address(factionA)), 1);
        (, uint256 lpAmount,,) = factionA.getStakingPosition(factionA.lastTokenId());
        factionA.withdrawFromPosition(factionA.lastTokenId(), lpAmount);
        (address faction, ) = superconductor.members(alice);
        assertEq(faction, address(0));
        assertEq(superconductor.totalFactionPlayers(address(factionA)), 0);
    }

    function testPoints() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.harvestPosition(factionA.lastTokenId());
        (, uint256 points) = superconductor.members(alice);
        assertApproxEqRel(points, lk99.blockRewardsPerDay(1) / 4, 1e13);
        vm.roll(startBlock + BLOCKS_PER_DAY * 3);
        factionA.harvestPosition(factionA.lastTokenId());
        (, points) = superconductor.members(alice);
        assertApproxEqRel(
            points,
            (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2) + lk99.blockRewardsPerDay(3)) / 4,
            1e13
        );
    }

    function testPointsMulti() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 2;
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        lpToken.transfer(bobby, lpTokenBalance);
        vm.startPrank(bobby);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(bobby, 0));
        (, uint256 points) = superconductor.members(bobby);
        assertApproxEqRel(points, lk99.blockRewardsPerDay(1) / 4 / 8 * 7, 1e13);
        vm.stopPrank();
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        (, points) = superconductor.members(alice);
        assertApproxEqRel(points, lk99.blockRewardsPerDay(1) / 4 / 8, 1e13);
    }

    function testPointsMultiFaction() public {
        lpToken.transfer(alice, 1_000 * 1e18);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(1_000 * 1e18, false);
        vm.stopPrank();
        lpToken.transfer(bobby, 10_000 * 1e18);
        vm.startPrank(bobby);
        lpToken.approve(address(factionB), UINT256_MAX);
        factionB.createPosition(10_000 * 1e18, false);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY);
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        (, uint256 alicePoints) = superconductor.members(alice);
        vm.stopPrank();
        vm.startPrank(bobby);
        factionB.harvestPosition(factionB.tokenOfOwnerByIndex(bobby, 0));
        (, uint256 bobbyPoints) = superconductor.members(bobby);
        assertApproxEqRel(alicePoints * 10, bobbyPoints, 1e13);
    }

    function testPointsQuadFactionWithReset() public {
        lpToken.transfer(alice, 100 * 1e18);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(100 * 1e18, false);
        vm.stopPrank();
        lpToken.transfer(bobby, 400 * 1e18);
        vm.startPrank(bobby);
        lpToken.approve(address(factionB), UINT256_MAX);
        factionB.createPosition(400 * 1e18, false);
        vm.stopPrank();
        lpToken.transfer(carie, 500 * 1e18);
        vm.startPrank(carie);
        lpToken.approve(address(factionC), UINT256_MAX);
        factionC.createPosition(500 * 1e18, false);
        vm.stopPrank();
        lpToken.transfer(danny, 1_000 * 1e18);
        vm.startPrank(danny);
        lpToken.approve(address(factionD), UINT256_MAX);
        factionD.createPosition(1_000 * 1e18, false);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY);
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        (, uint256 alicePoints) = superconductor.members(alice);
        vm.stopPrank();
        vm.startPrank(bobby);
        factionB.harvestPosition(factionB.tokenOfOwnerByIndex(bobby, 0));
        (, uint256 bobbyPoints) = superconductor.members(bobby);
        vm.stopPrank();
        vm.startPrank(carie);
        factionC.harvestPosition(factionC.tokenOfOwnerByIndex(carie, 0));
        (, uint256 cariePoints) = superconductor.members(carie);
        vm.stopPrank();
        vm.startPrank(danny);
        factionD.harvestPosition(factionD.tokenOfOwnerByIndex(danny, 0));
        (, uint256 dannyPoints) = superconductor.members(danny);
        uint256 totalPoints = superconductor.totalPoints();
        assertEq(alicePoints, totalPoints / 20);
        assertEq(bobbyPoints, totalPoints / 5);
        assertEq(cariePoints, totalPoints / 4);
        (, uint256 lpAmount,,) = factionD.getStakingPosition(factionD.lastTokenId());
        factionD.withdrawFromPosition(factionD.tokenOfOwnerByIndex(danny, 0), lpAmount);
        assertEq(alicePoints, totalPoints / 20);
        assertEq(bobbyPoints, totalPoints / 5);
        assertEq(cariePoints, totalPoints / 4);
        assertEq(superconductor.totalPoints(), totalPoints);
        (, dannyPoints) = superconductor.members(danny);
        assertEq(dannyPoints, 0);
    }
}
