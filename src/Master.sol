// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./interfaces/IFaction.sol";
import "./interfaces/ILK99.sol";
import "./interfaces/IMaster.sol";

contract Master is Ownable, IMaster {

    using SafeERC20 for ILK99;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each faction
    struct FactionInfo {
        uint256 lastRewardBlock; // Last block that distribution to this faction occurs
        uint256 reserve; // Pending rewards to distribute to the faction
    }

    ILK99 public immutable override lk99;

    mapping(address => FactionInfo) private _factionInfo;
    EnumerableSet.AddressSet private _factions; // All existing faction addresses

    uint256 public immutable startBlock; // The block at which farming starts

    constructor(ILK99 lk99_, uint256 startBlock_) {
        require(block.number < startBlock_ && startBlock_ >= lk99_.lastEmission(), "invalid start");
        lk99 = lk99_;
        startBlock = startBlock_;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event ClaimRewards(address indexed factionAddress, uint256 amount);
    event FactionAdded(address indexed factionAddress);
    event FactionUpdated(address indexed factionAddress, uint256 reserve, uint256 blockNumber);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check if a faction exists
     */
    modifier validateFaction(address factionAddress) {
        require(_factions.contains(factionAddress));
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Returns the number of factions
     */
    function factionsLength() public view returns (uint256) {
        return _factions.length();
    }

    function emissionRate() public view returns (uint256) {
        return lk99.currentEmissionRate() * 1e18;
    }

    /**
     * @dev Returns data of a given faction
     */
    function getFactionInfo(address factionAddress_) external view override returns (
        address factionAddress,
        uint256 lastRewardBlock,
        uint256 reserve,
        uint256 factionEmissionRate
    ) {
        FactionInfo memory faction = _factionInfo[factionAddress_];
        return (factionAddress_, faction.lastRewardBlock, faction.reserve, emissionRate().div(factionsLength()));
    }

    /**
     * @dev Returns current owner's address
     */
    function owner() public view virtual override(IMaster, Ownable) returns (address) {
        return Ownable.owner();
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /**
     * @dev Adds a new faction
     * param withUpdate should be set to true every time it's possible
     *
     * Must only be called by the owner
     */
    function add(IFaction faction) external onlyOwner {
        address factionAddress = address(faction);
        require(!_factions.contains(factionAddress), "Master.add: faction already exists");

        _massUpdateFactions();

        // add new faction
        _factionInfo[factionAddress] = FactionInfo({
            lastRewardBlock: startBlock,
            reserve: 0
        });
        _factions.add(factionAddress);

        emit FactionAdded(factionAddress);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Transfer to a faction its pending rewards in reserve, can only be called by the faction contract itself
     */
    function claimRewards() external override returns (uint256 rewardsAmount) {
        require(_factions.contains(msg.sender), "Master: only factions can claim rewards");

        _updateFaction(msg.sender);

        // updates caller's reserve
        FactionInfo storage faction = _factionInfo[msg.sender];
        uint256 reserve = faction.reserve;
        if (reserve == 0) {
            return 0;
        }
        faction.reserve = 0;

        emit ClaimRewards(msg.sender, reserve);
        return _safeRewardsTransfer(msg.sender, reserve);
    }

    /**
     * @dev Updates rewards states for all factions
     *
     * Be careful of gas spending
     */
    function massUpdateFactions() external {
        _massUpdateFactions();
    }

    /**
     * @dev Updates rewards states of the given faction to be up-to-date
     */
    function updateFaction(address faction) external validateFaction(faction) {
        _updateFaction(faction);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Updates rewards states for all factions
     *
     * Be careful of gas spending
     */
    function _massUpdateFactions() internal {
        uint256 length = _factions.length();
        for (uint256 index = 0; index < length; ++index) {
            _updateFaction(_factions.at(index));
        }
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes faction to not have enough tokens
     */
    function _safeRewardsTransfer(address to, uint256 amount) internal returns (uint256 effectiveAmount) {
        uint256 balance = lk99.balanceOf(address(this));

        if (amount > balance) {
            amount = balance;
        }

        lk99.safeTransfer(to, amount);
        return amount;
    }

    /**
     * @dev Updates rewards states of the given faction to be up-to-date
     *
     * Faction should be validated prior to calling this
     */
    function _updateFaction(address factionAddress) internal {
        FactionInfo storage faction = _factionInfo[factionAddress];

        if (block.number <= faction.lastRewardBlock) {
            return;
        }

        // do not allocate rewards if faction is not active
        if (IFaction(factionAddress).hasDeposits()) {
            // calculate how much LK99 rewards are expected to be received for this faction
            uint256 rewards = lk99.pendingEmissions(faction.lastRewardBlock).div(factionsLength());

            // claim expected rewards from the token
            // use returns effective minted amount instead of expected amount
            (rewards) = lk99.claimMasterRewards(rewards);

            // updates faction data
            faction.reserve = faction.reserve.add(rewards);
        }

        faction.lastRewardBlock = block.number;

        emit FactionUpdated(factionAddress, faction.reserve, block.number);
    }
}
