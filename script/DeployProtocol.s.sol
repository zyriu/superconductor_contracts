// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "forge-std/Script.sol";
import "../src/LK99.sol";
import "../src/Master.sol";
import "../src/FactionFactory.sol";
import "../src/Superconductor.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IRouter.sol";


contract DeployProtocol is Script {

  address constant public factory = 0xFDa619b6d20975be80A10332cD39b9a4b0FAa8BB;
  address constant public router = 0x327Df1E6de05895d2ab08513aaDD9313Fe505d86;
  address constant public WETH = 0x4200000000000000000000000000000000000006;

  LK99 constant public lk99 = LK99(0x0);
  address constant public lpToken = 0x0000000000000000000000000000000000000006;

  uint256 constant public START_BLOCK = 0;

  uint256 public BLOCKS_PER_DAY = 43_200;

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    Master master = new Master(lk99, START_BLOCK);
    lk99.initializeEmissions(START_BLOCK, 98_000_000 * 1e18);
    lk99.initializeMasterAddress(address(master));
    lk99.excludeFromBurn(address(master), true);

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
