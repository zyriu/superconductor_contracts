// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ILK99.sol";

contract LK99 is Ownable, ERC20("Superconductor Finance", "LK99"), ILK99 {

  using SafeMath for uint256;

  uint256 public constant BLOCKS_PER_DAY = 43_200; // 1 block per 2 seconds on Base

  bool public blacklistRenounced;
  mapping(address => bool) public blacklisted;
  mapping(address => bool) private _isExcludedFromBurn;

  uint256 public currentMaxSupply = 200_000_000 * 1e18;

  uint256 public deployedTimestamp;
  bool public initialized;
  uint256 public emissionStart;
  uint256 public override lastEmission;

  uint256 public masterReserve; // Pending rewards for the master
  address public masterAddress;

  uint256 public constant BURN_DENOMINATOR = 10000;
  uint256 public constant BURN_PERCENTAGE = 210; // 2.1%

  uint256 public constant SUPERCONDUCTOR_CAPACITY_PER_DAY = 45; // 4.5%

  constructor(uint256 initialSupply) {
    require(initialSupply < currentMaxSupply, "invalid initial supply");

    deployedTimestamp = block.timestamp;
    _mint(msg.sender, initialSupply);
  }

  function initializeEmissions(uint256 emissionStart_, uint256 initializedSupply) external onlyOwner {
    require(block.timestamp >= deployedTimestamp + 2 weeks);
    require(!initialized);
    require(initializedSupply + totalSupply() <= currentMaxSupply, "invalid initial supply");
    require(emissionStart_ > block.number, "invalid emission start");

    initialized = true;

    _mint(msg.sender, initializedSupply);
    lastEmission = emissionStart_;
    emissionStart = emissionStart_;
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event ClaimMasterRewards(uint256 amount);
  event AllocationsDistributed(uint256 masterShare);
  event InitializeMasterAddress(address masterAddress);
  event InitializeEmissionStart(uint256 startTime);
  event UpdateEmissionRate(uint256 previousEmissionRate, uint256 newEmissionRate);

  /***********************************************/
  /****************** MODIFIERS ******************/
  /***********************************************/

  /*
   * @dev Throws error if called by any account other than the master
   */
  modifier onlyMaster() {
    require(msg.sender == masterAddress, "LK99: caller is not the master");
    _;
  }

  /**************************************************/
  /****************** PUBLIC VIEWS ******************/
  /**************************************************/

  /**
   * @dev Returns block rewards per block for a given day.
   */
  function blockRewardsPerDay(uint256 day) public pure returns (uint256) {
    if (day == 1) {
      return 3_500_000;
    } else if (day < 22) {
      return day.mul(100_000).add(3_500_000);
    } else {
      return 0;
    }
  }

  /**
   * @dev Returns day for emission computation
   */
  function currentDay() public view override returns (uint256) {
    if (!initialized) {
      return 0;
    }

    return block.number < emissionStart ? 0 : (block.number.sub(emissionStart)).div(BLOCKS_PER_DAY) + 1;
  }

  /**
   * @dev Returns current emission rate
   */
  function currentEmissionRate() public view override returns (uint256) {
    return blockRewardsPerDay(currentDay()).div(BLOCKS_PER_DAY);
  }

  function emissionsOver() external override view returns (bool) {
    return blockRewardsPerDay(currentDay()) == 0;
  }

  /*****************************************************************/
  /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
  /*****************************************************************/

  function burn(uint256 amount) external override {
    _burn(msg.sender, amount);
  }

  /**
   * @dev Sends to Master contract the asked "amount" from masterReserve
   *
   * Can only be called by the MasterContract
   */
  function claimMasterRewards(uint256 rewards) external override onlyMaster returns (uint256 effectiveAmount) {
    // update emissions
    emitAllocations();

    // cap asked amount with available reserve
    effectiveAmount = Math.min(masterReserve, rewards);

    // if no rewards to transfer
    if (effectiveAmount == 0) {
      return effectiveAmount;
    }

    // remove claimed rewards from reserve and transfer to master
    masterReserve = masterReserve.sub(effectiveAmount);
    super._transfer(address(this), masterAddress, effectiveAmount);
    emit ClaimMasterRewards(effectiveAmount);
  }

  /**
   * @dev Mint rewards and distribute it to master
   *
   * Master incentives are minted into this contract and claimed later by the master contract
   */
   function emitAllocations() public returns (uint256 newEmissions) {
     newEmissions = 0;

     uint256 circulatingSupply = totalSupply();
     uint256 blocksProcessed = lastEmission;

     // only emit if not up to date
     if (block.number > blocksProcessed && circulatingSupply < currentMaxSupply) {
       uint256 today = currentDay();
       uint256 start = emissionStart;
       for (uint256 day = blocksProcessed.sub(start).div(BLOCKS_PER_DAY) + 1; day <= today; day++) {
         uint256 blocksToProcess = BLOCKS_PER_DAY.sub(blocksProcessed.sub(start).sub((day - 1).mul(BLOCKS_PER_DAY)));
         uint256 emitFor = Math.min(blocksToProcess, block.number.sub(blocksProcessed));
         newEmissions = newEmissions.add(emitFor.mul(blockRewardsPerDay(day)).div(BLOCKS_PER_DAY).mul(1e18));
         blocksProcessed = blocksProcessed.add(emitFor);
       }

       // cap new emissions if exceeding max supply
       if (currentMaxSupply < circulatingSupply.add(newEmissions)) {
         newEmissions = currentMaxSupply.sub(circulatingSupply);
       }

       lastEmission = block.number;

       // add master shares to its claimable reserve
       masterReserve = masterReserve.add(newEmissions);

       // mint shares
       _mint(address(this), newEmissions);

       emit AllocationsDistributed(newEmissions);
     }
  }

  function pendingEmissions(uint256 lastRewardBlock) external override view returns (uint256 emissions) {
    emissions = 0;

    uint256 circulatingSupply = totalSupply();

    if (block.number > lastRewardBlock && circulatingSupply < currentMaxSupply) {
      uint256 today = currentDay();
      uint256 start = emissionStart;
      for (uint256 day = lastRewardBlock.sub(start).div(BLOCKS_PER_DAY) + 1; day <= today; day++) {
        uint256 blocksToProcess = BLOCKS_PER_DAY.sub(lastRewardBlock.sub(start).sub((day - 1).mul(BLOCKS_PER_DAY)));
        uint256 emitFor = Math.min(blocksToProcess, block.number.sub(lastRewardBlock));
        emissions = emissions.add(emitFor.mul(blockRewardsPerDay(day)).div(BLOCKS_PER_DAY).mul(1e18));
        lastRewardBlock = lastRewardBlock.add(emitFor);
      }

      // cap new emissions if exceeding max supply
      if (currentMaxSupply < circulatingSupply.add(emissions)) {
        emissions = currentMaxSupply.sub(circulatingSupply);
      }
    }
  }

  function superconductorCapacity() external override view returns (uint256 capacity) {
    if (!initialized) {
      return 0;
    }

    capacity = currentDay().mul(SUPERCONDUCTOR_CAPACITY_PER_DAY).add(10);

    // max value is 100%
    if (capacity > 1000) {
      capacity = 1000;
    }
  }

  /*****************************************************************/
  /****************** EXTERNAL OWNABLE FUNCTIONS  ******************/
  /*****************************************************************/

  /**
   * @dev Blacklist an address
   *
   * Must only be called by the owner
   */
  function blacklist(address _addr, bool toggle) public onlyOwner {
    require(blacklistRenounced == false);
    blacklisted[_addr] = toggle;
  }

  /**
   * @dev Exclude from burn
   *
   * Must only be called by the owner
   */
  function excludeFromBurn(address _addr, bool toggle) public onlyOwner {
    _isExcludedFromBurn[_addr] = toggle;
  }

  /**
   * @dev Setup Master contract address
   *
   * Can only be initialized once
   * Must only be called by the owner
   */
  function initializeMasterAddress(address masterAddress_) external onlyOwner {
    require(masterAddress == address(0), "initializeMasterAddress: master already initialized");
    require(masterAddress_ != address(0), "initializeMasterAddress: master initialized to zero address");

    masterAddress = masterAddress_;
    emit InitializeMasterAddress(masterAddress_);
  }

  /**
   * @dev Renounce blacklist function
   *
   * Must only be called by the owner
   */
  function renounceBlacklist() public onlyOwner {
    blacklistRenounced = true;
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  function _burn(address account, uint256 amount) internal override {
    super._burn(account, amount);
    currentMaxSupply -= amount;
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");
    require(!blacklisted[from], "Sender blacklisted");
    require(!blacklisted[to], "Receiver blacklisted");

    if (amount == 0) {
      super._transfer(from, to, 0);
      return;
    }

    // exclude EOA to EOA from burn
    if (!_isExcludedFromBurn[from] && !_isExcludedFromBurn[to] && (Address.isContract(from) || Address.isContract(to))) {
      uint256 fees = amount.mul(BURN_PERCENTAGE).div(BURN_DENOMINATOR);
      if (fees > 0) {
        _burn(from, fees);
      }

      amount -= fees;
    }

    super._transfer(from, to, amount);
  }
}
