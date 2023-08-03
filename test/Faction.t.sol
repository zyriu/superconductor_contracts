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


contract FactionTest is Test {

    address owner;
    address alice = address(0x69691);
    address bobby = address(0x69692);
    address carie = address(0x69693);
    address danny = address(0x69694);

    IERC20 lpToken;
    Faction factionA;
    Faction factionB;
    Faction factionC;
    Faction factionD;

    uint256 constant PLEDGE_FEE = 420;
    uint256 constant PLEDGE_DENOMINATOR = 10000;
    uint256 constant PLEDGE_REMAIN = PLEDGE_DENOMINATOR - PLEDGE_FEE;

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

    receive() external payable {}

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

        superconductor = new Superconductor(owner, router, address(lk99), WETH, address(lpToken));
        factionFactory = new FactionFactory(lk99, master, address(superconductor), PLEDGE_FEE);
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

    function testAddToPosition() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance / 2, false);
        uint256 tokenId = factionA.lastTokenId();
        assertEq(factionA.pendingRewards(tokenId), 0);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.addToPosition(tokenId, lpTokenBalance / 2);
        assertApproxEqRel(
            factionA.pendingRewards(tokenId),
            lk99.blockRewardsPerDay(1) / 4 * 1e18,
            1e6
        );
        vm.roll(startBlock + BLOCKS_PER_DAY * 2);
        (, uint256 lpAmount,,) = factionA.getStakingPosition(factionA.lastTokenId());
        factionA.withdrawFromPosition(tokenId, lpAmount);
        assertApproxEqRel(
            lk99.balanceOf(alice),
            (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4 * 145 / 1000 * 1e18,
            1e6
        );
    }

    function testAddToPositionLocked() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance / 2, true);
        uint256 tokenId = factionA.lastTokenId();
        assertEq(factionA.pendingRewards(tokenId), 0);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.addToPosition(tokenId, lpTokenBalance / 2);
        assertApproxEqRel(factionA.pendingRewards(tokenId), lk99.blockRewardsPerDay(1) / 4 * 1e18, 1e2);
        vm.roll(startBlock + BLOCKS_PER_DAY * 2);
        (, uint256 lpAmount,,) = factionA.getStakingPosition(factionA.lastTokenId());
        vm.expectRevert("position is locked");
        factionA.withdrawFromPosition(tokenId, lpAmount);
        factionA.harvestPosition(tokenId);
        assertApproxEqRel(
            factionA.pendingRewards(tokenId),
            (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4 * 1e18,
            1e10
        );
    }

    function testCreatePositionZeroAmount() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), lpTokenBalance);
        vm.expectRevert("INSUFFICIENT_LIQUIDITY_BURNED");
        factionA.createPosition(0, false);
    }

    function testCreatePosition() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 2;
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), lpTokenBalance);
        factionA.createPosition(lpTokenBalance, false);
        uint256 tokenId = factionA.lastTokenId();
        (bool isLocked, uint256 amount, uint256 amountWithMultiplier, uint256 rewardDebt) =
            factionA.getStakingPosition(tokenId);
        assertEq(isLocked, false);
        assertApproxEqRel(amount, lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR, 1e2);
        assertApproxEqRel(amountWithMultiplier, lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR, 1e2);
        assertEq(rewardDebt, 0);
        assertEq(factionA.pendingRewards(tokenId), 0);
        vm.stopPrank();
        lpToken.transfer(bobby, lpTokenBalance);
        vm.startPrank(bobby);
        lpToken.approve(address(factionA), lpTokenBalance);
        factionA.createPosition(lpTokenBalance, false);
        tokenId = factionA.lastTokenId();
        (isLocked, amount, amountWithMultiplier, rewardDebt) = factionA.getStakingPosition(tokenId);
        assertEq(isLocked, false);
        assertApproxEqRel(amount, lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR, 1e2);
        assertApproxEqRel(amountWithMultiplier, lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR, 1e2);
        assertEq(rewardDebt, 0);
        assertEq(factionA.pendingRewards(tokenId), 0);
    }

    function testCreatePositionDoubleFaction() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance / 2, true);
        lpToken.approve(address(factionB), UINT256_MAX);
        vm.expectRevert("user is already in a faction");
        factionB.createPosition(lpTokenBalance / 2, true);
        vm.expectRevert("user is already in a faction");
        factionA.createPosition(lpTokenBalance / 2, true);
    }

    function testCreatePositionLocked() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        uint256 tokenId = factionA.lastTokenId();
        (bool isLocked, uint256 amount, uint256 amountWithMultiplier, uint256 rewardDebt) =
        factionA.getStakingPosition(tokenId);
        assertEq(isLocked, true);
        assertApproxEqRel(amount, lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR, 1e2);
        assertApproxEqRel(
            amountWithMultiplier,
            lpTokenBalance * PLEDGE_REMAIN / PLEDGE_DENOMINATOR * factionA.LOCK_BOOST_MULTIPLIER(),
            1e2
        );
        assertEq(rewardDebt, 0);
        assertEq(factionA.pendingRewards(tokenId), 0);
    }

    function testHarvestPosition(uint256 lpAmount) public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 2;
        lpToken.transfer(alice, lpTokenBalance);
        lpToken.transfer(bobby, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(bobby);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY);
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        vm.stopPrank();
        vm.startPrank(bobby);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(bobby, 0));
        assertEq(lk99.balanceOf(alice), lk99.balanceOf(bobby));
    }

    function testHarvestPositionHaircut() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpToken.balanceOf(alice), false);
        vm.roll(startBlock + BLOCKS_PER_DAY * 2);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        assertApproxEqRel(
            lk99.balanceOf(alice),
            (lk99.blockRewardsPerDay(1) + lk99.blockRewardsPerDay(2)) / 4 * 145 / 1000 * 1e18,
            1e2
        ); // 14.5% on third day
    }

    function testHarvestPositionNoHaircut() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpToken.balanceOf(alice), false);
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        assertApproxEqRel(lk99.balanceOf(alice), 24_125_000 * 1e18, 1e2);
    }

    function testHarvestPositionLocked() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        uint256 tokenId = factionA.lastTokenId();
        factionA.harvestPosition(tokenId);
        assertEq(lk99.balanceOf(alice), 0);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.harvestPosition(tokenId);
        assertApproxEqRel(factionA.pendingRewards(tokenId), lk99.blockRewardsPerDay(1) / 4 * 1e18, 1e2);
    }

    function testHarvestPositionLockedHaircut() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 2;
        lpToken.transfer(alice, lpTokenBalance);
        lpToken.transfer(bobby, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(bobby);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY);
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        vm.stopPrank();
        vm.startPrank(bobby);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(bobby, 0));
        assertApproxEqRel(lk99.balanceOf(alice), lk99.blockRewardsPerDay(1) / 4 / 8 * 100 / 1000 * 1e18, 1e14);
        assertApproxEqRel(
            factionA.pendingRewards(factionA.tokenOfOwnerByIndex(bobby, 0)),
            lk99.blockRewardsPerDay(1) / 4 * 7 / 8 * 1e18,
            1e4
        );
    }

    function testHarvestPositionMultiFaction() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 4;
        lpToken.transfer(alice, lpTokenBalance);
        lpToken.transfer(bobby, lpTokenBalance);
        lpToken.transfer(carie, lpTokenBalance);
        lpToken.transfer(danny, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(bobby);
        lpToken.approve(address(factionB), UINT256_MAX);
        factionB.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(carie);
        lpToken.approve(address(factionC), UINT256_MAX);
        factionC.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(danny);
        lpToken.approve(address(factionD), UINT256_MAX);
        factionD.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY);
        vm.prank(alice);
        factionA.harvestPosition(1);
        vm.prank(bobby);
        factionB.harvestPosition(1);
        vm.prank(carie);
        factionC.harvestPosition(1);
        vm.prank(danny);
        factionD.harvestPosition(1);
        assertApproxEqRel(lk99.balanceOf(alice), lk99.blockRewardsPerDay(1) / 4 * 100 / 1000 * 1e18, 1e2);
        assertApproxEqRel(lk99.balanceOf(bobby), lk99.blockRewardsPerDay(1) / 4 * 100 / 1000 * 1e18, 1e2);
        assertApproxEqRel(lk99.balanceOf(carie), lk99.blockRewardsPerDay(1) / 4 * 100 / 1000 * 1e18, 1e2);
        assertApproxEqRel(lk99.balanceOf(danny), lk99.blockRewardsPerDay(1) / 4 * 100 / 1000 * 1e18, 1e2);
    }

    function testLockPositionBoostRatio() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner) / 2;
        lpToken.transfer(alice, lpTokenBalance);
        lpToken.transfer(bobby, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        vm.stopPrank();
        vm.startPrank(bobby);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        vm.stopPrank();
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        vm.startPrank(alice);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(alice, 0));
        vm.stopPrank();
        vm.startPrank(bobby);
        factionA.harvestPosition(factionA.tokenOfOwnerByIndex(bobby, 0));
        assertApproxEqRel(lk99.balanceOf(alice) * factionA.LOCK_BOOST_MULTIPLIER(), lk99.balanceOf(bobby), 1e2);
    }

    function testPendingRewards() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        uint256 tokenId = factionA.lastTokenId();
        assertEq(factionA.pendingRewards(tokenId), 0);
        vm.roll(startBlock + BLOCKS_PER_DAY);
        factionA.updateFaction();
        assertApproxEqRel(factionA.pendingRewards(tokenId), 875_000 * 1e18, 1e2);
    }

    function testWithdrawFromPosition() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, false);
        uint256 tokenId = factionA.lastTokenId();
        (, uint256 lpAmount, , ) = factionA.getStakingPosition(tokenId);
        factionA.withdrawFromPosition(tokenId, lpAmount);
        assertEq(lpToken.balanceOf(alice), lpAmount);
        (address faction, ) = superconductor.members(alice);
        assertEq(faction, address(0));
    }

    function testWithdrawFromPositionLocked() public {
        uint256 lpTokenBalance = lpToken.balanceOf(owner);
        lpToken.transfer(alice, lpTokenBalance);
        vm.startPrank(alice);
        lpToken.approve(address(factionA), UINT256_MAX);
        factionA.createPosition(lpTokenBalance, true);
        uint256 tokenId = factionA.lastTokenId();
        vm.expectRevert("position is locked");
        factionA.withdrawFromPosition(tokenId, 1);
        vm.roll(startBlock + BLOCKS_PER_DAY * 21);
        (, uint256 lpAmount, , ) = factionA.getStakingPosition(tokenId);
        factionA.withdrawFromPosition(tokenId, lpAmount);
        assertEq(lpToken.balanceOf(alice), lpAmount);
        (address faction, ) = superconductor.members(alice);
        assertEq(faction, address(0));
    }
}
