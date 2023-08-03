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
import "../src/interfaces/IPair.sol";
import "../src/interfaces/IRouter.sol";


contract AMMTest is Test {

    address owner;

    IERC20 lpToken;

    uint256 INITIAL_LK99_SUPPLY = 2_000_000 * 1e18;
    uint256 BLOCKS_PER_DAY = 43_200;

    LK99 lk99;

    address constant factory = 0xFDa619b6d20975be80A10332cD39b9a4b0FAa8BB;
    address constant router = 0x327Df1E6de05895d2ab08513aaDD9313Fe505d86;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    string BASE_RPC = vm.envString("BASE_RPC");

    receive() payable external {}

    function setUp() public {
        vm.selectFork(vm.createFork(BASE_RPC));
        owner = address(this);
        lk99 = new LK99(INITIAL_LK99_SUPPLY);

        lpToken = IERC20(IFactory(factory).createPair(address(lk99), WETH));
        lk99.approve(router, UINT256_MAX);
        IRouter(router).addLiquidityETH{value: 5 ether}(
            address(lk99),
            2_000_000 * 1e18,
            2_000_000 * 1e18,
            5 ether,
            owner,
            UINT256_MAX
        );
    }

    function testRemoveLiquidity() public {
        uint256 liquidity = lpToken.balanceOf(owner);
        lpToken.approve(router, UINT256_MAX);
        IRouter(router).removeLiquidityETHSupportingFeeOnTransferTokens(
            address(lk99),
            liquidity,
            0,
            0,
            owner,
            block.timestamp
        );
    }

    function testSwap() public {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(lk99);
        (uint256 reserveIn, uint256 reserveOut, ) = IPair(address(lpToken)).getReserves();
        uint256 amountMin = IRouter(router).getAmountOut(1 ether, reserveIn, reserveOut);
        vm.expectRevert("PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IRouter(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            amountMin,
            path,
            owner,
            block.timestamp
        );
        amountMin = amountMin * 95 / 100;
        IRouter(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            amountMin,
            path,
            owner,
            block.timestamp
        );
    }
}
