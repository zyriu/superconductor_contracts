// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Faction.sol";
import "./interfaces/IFactionFactory.sol";
import "./interfaces/IMaster.sol";


contract FactionFactory is IFactionFactory, Ownable {

    IERC20 public immutable lk99;
    IMaster public immutable master;
    uint256 public immutable fees;
    address public immutable override superconductor;

    mapping(address => bool) public override isFaction;
    address[4] public override factions;
    uint256 public override factionsAmount;

    constructor(IERC20 lk99_, IMaster master_, address superconductor_, uint256 fees_) {
        lk99 = lk99_;
        master = master_;
        superconductor = superconductor_;
        fees = fees_;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event FactionCreated(address indexed lpToken, address faction);

    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    function createFaction(address lpToken) external onlyOwner returns (address faction) {
        require(factionsAmount < 4, "max faction amount reached");

        bytes memory bytecode_ = _bytecode();
        bytes32 salt = keccak256(abi.encodePacked(lpToken, factionsAmount));
        /* solhint-disable no-inline-assembly */
        assembly {
            faction := create2(0, add(bytecode_, 32), mload(bytecode_), salt)
        }
        require(faction != address(0), "failed");

        Faction(faction).initialize(master, lk99, IERC20(lpToken), fees);
        factions[factionsAmount] = faction;
        factionsAmount += 1;
        isFaction[faction] = true;

        emit FactionCreated(lpToken, faction);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    function _bytecode() internal pure virtual returns (bytes memory) {
        return type(Faction).creationCode;
    }
}
