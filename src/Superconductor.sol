// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IFactionFactory.sol";
import "./interfaces/ILK99.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/ISuperconductor.sol";
import "./LK99.sol";

contract Superconductor is ISuperconductor, Ownable {

    using SafeMath for uint256;

    uint256 constant internal UINT256_MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    address public pledge;
    address public immutable lk99;
    address public immutable lpToken;
    address public immutable router;
    address public immutable WETH;
    address public factionFactory;

    bool private _initialized;

    mapping (address => uint256) public totalFactionPoints;
    mapping (address => uint256) public totalFactionPlayers;
    uint256 public totalPoints;

    struct Member {
        address faction;
        uint256 points;
    }

    mapping (address => Member) public members;

    constructor (address pledge_, address router_, address lk99_, address WETH_, address lpToken_) {
        pledge = pledge_;
        router = router_;
        lk99 = lk99_;
        WETH = WETH_;
        lpToken = lpToken_;
    }

    receive() external payable {}

    function initialize(address factionFactory_) external onlyOwner {
        require(_initialized == false);
        _initialized = true;
        factionFactory = factionFactory_;
    }

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    modifier onlyFaction() {
        require(IFactionFactory(factionFactory).isFaction(msg.sender), "UNAUTHORIZED");
        _;
    }

    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    /**
     * @dev Compute points pro rate liquidity provided in each faction
     */
    function creditPoints(address member, uint256 points) external override onlyFaction {
        uint256 lpHeldByFaction = IERC20(lpToken).balanceOf(msg.sender);
        uint256 pointsToCredit = points.mul(lpHeldByFaction).div(_getTotalLPStaked());

        // credit points to faction
        totalFactionPoints[msg.sender] = totalFactionPoints[msg.sender].add(pointsToCredit);

        // add to total
        totalPoints = totalPoints.add(pointsToCredit);

        // credit points to member
        members[member].points = members[member].points.add(pointsToCredit);
    }

    /**
     * @dev Dispatch pool fees and burn
     */
    function dispatch() external override onlyFaction {
        uint256 initialETHAmount = address(this).balance;

        _removeLiquidity();

        // dispatch pledge
        uint256 dispatchAmount = address(this).balance.sub(initialETHAmount);
        uint256 pledgeAmount = dispatchAmount.mul(2100).div(10000);
        (bool success,) = pledge.call{value: pledgeAmount}("");
        require(success);

        // burn LK99
        ILK99(lk99).burn(ILK99(lk99).balanceOf(address(this)));
    }

    function joinFaction(address member) external override onlyFaction {
        require(!ILK99(lk99).emissionsOver(), "superconductor is fully charged");
        require(members[member].faction == address(0), "user is already in a faction");
        members[member].faction = msg.sender;
        totalFactionPlayers[msg.sender] = totalFactionPlayers[msg.sender].add(1);
    }

    function leaveFaction(address member) external override onlyFaction {
        require(members[member].faction != address(0), "user isn't in a faction");
        delete members[member];
        totalFactionPlayers[msg.sender] = totalFactionPlayers[msg.sender].sub(1);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    function _getTotalLPStaked() internal view returns (uint256 totalLPStaked) {
        uint256 length = IFactionFactory(factionFactory).factionsAmount();

        for (uint256 k = 0; k < length; k++) {
            totalLPStaked = totalLPStaked.add(IERC20(lpToken).balanceOf(IFactionFactory(factionFactory).factions(k)));
        }
    }

    /**
     * @dev Remove liquidity from pool prior to dispatch
     */
    function _removeLiquidity() internal {
        uint256 balance = IERC20(lpToken).balanceOf(address(this));

        if (IERC20(lpToken).allowance(address(this), address(router)) < balance) {
            IERC20(lpToken).approve(router, UINT256_MAX);
        }

        IRouter(router).removeLiquidityETHSupportingFeeOnTransferTokens(
            lk99,
            balance,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
