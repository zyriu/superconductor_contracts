// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "forge-std/Script.sol";
import "../src/LK99.sol";

contract DeployToken is Script {

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    LK99 lk99 = new LK99(2_000_000 * 1e18);
    lk99.excludeFromBurn(devWallet, true);

    vm.stopBroadcast();
  }
}
