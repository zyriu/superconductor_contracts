// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {

    constructor (string memory name_, string memory symbol_, uint8 decimals_, uint256 supply) ERC20(name_, symbol_) {
      _setupDecimals(decimals_);
      _mint(msg.sender, supply);
    }
}
