// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "forge-std/Script.sol";
import "../src/LK99.sol";
import "../src/Master.sol";
import "../src/FactionFactory.sol";
import "../src/Superconductor.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IRouter.sol";


contract DeployTestnet is Script {

  uint256 public BLOCKS_PER_DAY = 43_200;

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    uint256 startBlock = block.number + BLOCKS_PER_DAY;

    LK99 lk99 = new LK99(100_000_000 * 1e18);
    Master master = new Master(lk99, startBlock);
    lk99.initializeMasterAddress(address(master));
    lk99.excludeFromBurn(address(master), true);

    address lpToken = IFactory(factory).createPair(address(lk99), WETH);
    lk99.approve(router, UINT256_MAX);
    IRouter(router).addLiquidityETH{value: 1 ether}(
      address(lk99),
      400_000 * 1e18,
      400_000 * 1e18,
      1 ether,
      devWallet,
      UINT256_MAX
    );

    Superconductor superconductor = new Superconductor(devWallet, router, address(lk99), WETH, lpToken);
    FactionFactory factionFactory = new FactionFactory(lk99, master, address(superconductor), 420);
    superconductor.initialize(address(factionFactory));

    address copper = factionFactory.createFaction(lpToken);
    address oxide = factionFactory.createFaction(lpToken);
    address phosphorus = factionFactory.createFaction(lpToken);
    address sulfate = factionFactory.createFaction(lpToken);

    lk99.excludeFromBurn(copper, true);
    master.add(IFaction(copper));
    lk99.excludeFromBurn(oxide, true);
    master.add(IFaction(oxide));
    lk99.excludeFromBurn(phosphorus, true);
    master.add(IFaction(phosphorus));
    lk99.excludeFromBurn(sulfate, true);
    master.add(IFaction(sulfate));

    vm.stopBroadcast();
  }
}
