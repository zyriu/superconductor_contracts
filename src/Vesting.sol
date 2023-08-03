// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vesting is Ownable {

  using SafeMath for uint256;

  uint256 constant internal UINT256_MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  address public immutable lk99;

  uint256 public startBlock;
  uint256 public constant VESTING_DURATION = 43_200 * 21;
  uint256 public constant TOTAL_VESTING_AMOUNT = 30_000_000 * 1e18;

  bool public initialized;

  struct Vester {
    uint256 totalAmount;
    uint256 vestedAmount;
    uint256 lastClaimBlock;
    uint256 vestingDuration;
  }

  mapping (address => Vester) public vesters;

  event Claim(address indexed vester, uint256 amount);

  constructor(address lk99_) {
    lk99 = lk99_;
  }

  function initializeVesting(uint256 startBlock_) external onlyOwner {
    require(!initialized);

    IERC20(lk99).transferFrom(msg.sender, address(this), TOTAL_VESTING_AMOUNT);

    vesters[owner()] = Vester(10_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x1)] = Vester(10_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x2)] = Vester(4_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x3)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x4)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x5)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x6)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x7)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);
    vesters[address(0x8)] = Vester(1_000_000 * 1e18, 0, startBlock_, VESTING_DURATION);

    startBlock = startBlock_;
    initialized = true;
  }

  function claim() external {
    Vester storage vester = vesters[msg.sender];

    require(block.number >= vester.lastClaimBlock, "nothing to claim");

    uint256 amount = block.number.sub(vester.lastClaimBlock).mul(vester.totalAmount).div(vester.vestingDuration);
    uint256 remainingAmount = vester.totalAmount.sub(vester.vestedAmount);
    if (amount > remainingAmount) {
      amount = remainingAmount;
    }

    vester.lastClaimBlock = block.number;
    vester.vestedAmount = vester.vestedAmount + amount;

    IERC20(lk99).transfer(msg.sender, amount);

    emit Claim(msg.sender, amount);
  }

  function claimable(address vester) external view returns (uint256 amount) {
    Vester storage vester = vesters[msg.sender];
    amount = block.number.sub(vester.lastClaimBlock).mul(vester.totalAmount).div(vester.vestingDuration);
    uint256 remainingAmount = vester.totalAmount.sub(vester.vestedAmount);

    if (amount > remainingAmount) {
      amount = remainingAmount;
    }
  }

  function slash(address vester) external onlyOwner {
    Vester storage vester = vesters[vester];
    Vester storage masterVester = vesters[msg.sender];

    uint256 amountRemaining = vester.totalAmount.sub(vester.vestedAmount);
    masterVester.totalAmount = masterVester.totalAmount.add(amountRemaining);
    uint256 elapsedDuration = block.number.sub(vester.lastClaimBlock);
    masterVester.vestingDuration = masterVester.vestingDuration.sub(elapsedDuration);

    vester.totalAmount = 0;
    vester.vestedAmount = 0;
    vester.lastClaimBlock = UINT256_MAX;
  }
}
