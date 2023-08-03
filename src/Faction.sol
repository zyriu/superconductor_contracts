// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IFaction.sol";
import "./interfaces/IFactionFactory.sol";
import "./interfaces/IMaster.sol";
import "./interfaces/INFTHandler.sol";
import "./interfaces/ISuperconductor.sol";

contract Faction is ReentrancyGuard, IFaction, ERC721("Superconductor Faction", "SpF99") {

    using Address for address;
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Counters.Counter private _tokenIds;

    address public immutable factory; // FactionFactory contract's address
    IMaster public master; // Address of the master
    bool public initialized;

    IERC20 private _lpToken; // Deposit token contract's address
    IERC20 private _lk99; // LK99 contract's address
    uint256 private _lpSupply; // Sum of deposit tokens on this pool
    uint256 private _lpSupplyWithMultiplier; // Sum of deposit token on this faction including the user's total multiplier
    uint256 private _accRewardsPerShare; // Accumulated Rewards (staked token) per share, times 1e18. See below

    uint256 public fees;
    uint256 public constant LOCK_BOOST_MULTIPLIER = 7; // x7, max boost that can be earned from locking
    uint256 public constant FEES_DENOMINATOR = 10000;

    struct StakingPosition {
        bool isLocked;
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 pendingLK99Rewards; // Non harvested LK99 rewards
        uint256 rewardDebt; // Reward debt
    }

    // readable via getStakingPosition
    mapping(uint256 => StakingPosition) internal _stakingPositions; // Info of each NFT position that stakes LP tokens

    constructor() {
        factory = msg.sender;
    }

    function initialize(IMaster master_, IERC20 lk99_, IERC20 lpToken, uint256 fees_) external {
        require(msg.sender == factory && !initialized);
        _lpToken = lpToken;
        master = master_;
        _lk99 = lk99_;
        fees = fees_;
        initialized = true;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event AddToPosition(uint256 indexed tokenId, address user, uint256 amount);
    event CreatePosition(uint256 indexed tokenId, uint256 amount);
    event FactionUpdated(uint256 lastRewardBlock, uint256 accRewardsPerShare);
    event HarvestPointsOnly(uint256 indexed tokenId, address to, uint256 pending);
    event HarvestPosition(uint256 indexed tokenId, address to, uint256 pending);
    event WithdrawFromPosition(uint256 indexed tokenId, uint256 amount);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    modifier requireOnlyOwnerOf(uint256 tokenId) {
        require(_exists(tokenId), "ERC721: query for nonexistent token");
        require(msg.sender == ERC721.ownerOf(tokenId), "not owner");
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Returns true if "tokenId" is an existing spNFT id
     */
    function exists(uint256 tokenId) external view override returns (bool) {
        return ERC721._exists(tokenId);
    }

    /**
     * @dev Returns general "pool" info for this contract
    */
    function getFactionInfo() external view override returns (
        address lpToken,
        address lk99,
        uint256 lastRewardBlock,
        uint256 accRewardsPerShare,
        uint256 lpSupply
    ) {
        (, lastRewardBlock, , ) = master.getFactionInfo(address(this));
        return (address(_lpToken), address(_lk99), lastRewardBlock, _accRewardsPerShare, _lpSupply);
    }

    /**
     * @dev Returns a position info
     */
    function getStakingPosition(uint256 tokenId) external view override returns (
        bool isLocked,
        uint256 amount,
        uint256 amountWithMultiplier,
        uint256 rewardDebt
    ) {
        StakingPosition storage position = _stakingPositions[tokenId];
        return (position.isLocked, position.amount, position.amountWithMultiplier, position.rewardDebt);
    }

    /**
     * @dev Returns true if this pool currently has deposits
     */
    function hasDeposits() external view override returns (bool) {
        return _lpSupply > 0;
    }

    /**
     * @dev Returns last minted NFT id
     */
    function lastTokenId() external view returns (uint256) {
        return _tokenIds.current();
    }

    /**
     * @dev Returns this contract's owner (= master contract's owner)
     */
    function owner() public view returns (address) {
        return master.owner();
    }

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId) external view returns (uint256) {
        StakingPosition storage position = _stakingPositions[tokenId];

        uint256 accRewardsPerShare = _accRewardsPerShare;
        (, uint256 lastRewardBlock, uint256 reserve, uint256 factionEmissionRate) = master.getFactionInfo(address(this));

        // recompute accRewardsPerShare if not up to date
        if ((reserve > 0 || block.number > lastRewardBlock) && _lpSupply > 0) {
            uint256 duration = block.number.sub(lastRewardBlock);
            // adding reserve here in case master has been synced but not the pool
            uint256 tokenRewards = duration.mul(factionEmissionRate).add(reserve);
            accRewardsPerShare = accRewardsPerShare.add(tokenRewards.mul(1e18).div(_lpSupply));
        }

        return position.amountWithMultiplier.mul(accRewardsPerShare).div(1e18).sub(position.rewardDebt).add(position.pendingLK99Rewards);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Add to an existing staking position
     *
     * Can only be called by spNFTs' owner
     */
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external nonReentrant requireOnlyOwnerOf(tokenId) {
        require(amountToAdd > 0, "0 amount");

        _updateFaction();
        address nftOwner = ERC721.ownerOf(tokenId);

        StakingPosition storage position = _stakingPositions[tokenId];

        // store rewards as adding doesn't harvest
        _harvestPosition(tokenId, address(0));

        // handle tokens with transfer tax
        amountToAdd = _transferSupportingFeeOnTransfer(msg.sender, amountToAdd);

        // update position
        position.amount = position.amount.add(amountToAdd);
        _lpSupply = _lpSupply.add(amountToAdd);
        _updateBoostMultiplierInfoAndRewardDebt(position);

        _checkOnAddToPosition(nftOwner, tokenId, amountToAdd);
        emit AddToPosition(tokenId, msg.sender, amountToAdd);
    }

    /**
     * @dev Create a staking position
     */
    function createPosition(uint256 amount, bool lock) external nonReentrant {
        _updateFaction();

        // handle tokens with transfer tax
        amount = _transferSupportingFeeOnTransfer(msg.sender, amount);
        require(amount != 0, "zero amount");

        // check for lock
        uint256 amountWithMultiplier = lock ? amount.mul(LOCK_BOOST_MULTIPLIER) : amount;

        // mint NFT position token
        uint256 currentTokenId = _mintNextTokenId(msg.sender);

        // create position
        _stakingPositions[currentTokenId] = StakingPosition({
            amount: amount,
            amountWithMultiplier: amountWithMultiplier,
            isLocked: lock,
            pendingLK99Rewards: 0,
            rewardDebt : amount.mul(_accRewardsPerShare).div(1e18)
        });

        _superconductor().joinFaction(msg.sender);

        // update total lp supply
        _lpSupply = _lpSupply.add(amount);
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.add(amountWithMultiplier);

        emit CreatePosition(currentTokenId, amount);
    }

    /**
     * @dev Harvest points from a staking position and store yield in pending
     *
     * Can only be called by spNFTs' owner or approved address
     */
    function harvestPointsOnly(uint256 tokenId) external nonReentrant requireOnlyOwnerOf(tokenId) {
        _updateFaction();
        _harvestPointsOnly(tokenId, ERC721.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
    }

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFTs' owner or approved address
     */
    function harvestPosition(uint256 tokenId) external nonReentrant requireOnlyOwnerOf(tokenId) {
        _updateFaction();
        _harvestPosition(tokenId, ERC721.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
    }

    /**
     * @dev Add nonReentrant to ERC721.safeTransferFrom
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override(ERC721, IERC721) nonReentrant {
        ERC721.safeTransferFrom(from, to, tokenId, _data);
    }

    /**
     * @dev Add nonReentrant to ERC721.transferFrom
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) nonReentrant {
        ERC721.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     */
    function updateFaction() external nonReentrant {
        _updateFaction();
    }

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFTs' owner or approved address
     */
    function withdrawFromPosition(
        uint256 tokenId,
        uint256 amountToWithdraw
    ) external nonReentrant requireOnlyOwnerOf(tokenId) {
        _updateFaction();
        address nftOwner = ERC721.ownerOf(tokenId);
        _withdrawFromPosition(nftOwner, tokenId, amountToWithdraw);
        _checkOnWithdraw(nftOwner, tokenId, amountToWithdraw);
        _superconductor().leaveFaction(nftOwner);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev If NFTs' owner is a contract, confirm whether it's able to handle addToPosition
     */
    function _checkOnAddToPosition(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(abi.encodeWithSelector(
                INFTHandler(nftOwner).onNFTAddToPosition.selector, msg.sender, tokenId, lpAmount), "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFTs' owner is a contract, confirm whether it's able to handle rewards harvesting
     */
    function _checkOnNFTHarvest(address to, uint256 tokenId, uint256 lk99Amount) internal {
        address nftOwner = ERC721.ownerOf(tokenId);
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(abi.encodeWithSelector(
                INFTHandler(nftOwner).onNFTHarvest.selector, msg.sender, to, tokenId, lk99Amount), "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFTs' owner is a contract, confirm whether it's able to handle withdrawals
     */
    function _checkOnWithdraw(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(abi.encodeWithSelector(
                INFTHandler(nftOwner).onNFTWithdraw.selector, msg.sender, tokenId, lpAmount), "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev Destroys spNFT
     */
    function _destroyPosition(uint256 tokenId) internal {
        delete _stakingPositions[tokenId];
        ERC721._burn(tokenId);
    }

    function _harvestPointsOnly(uint256 tokenId, address to) internal {
        StakingPosition storage position = _stakingPositions[tokenId];

        // compute position's pending rewards
        uint256 pending = position.amountWithMultiplier.mul(_accRewardsPerShare).div(1e18).sub(
            position.rewardDebt
        );

        // credit points
        if (pending > 0) {
            _superconductor().creditPoints(ownerOf(tokenId), pending.div(1e18));
        }

        // transfer rewards
        if (pending > 0 || position.pendingLK99Rewards > 0) {
            position.pendingLK99Rewards = pending.add(position.pendingLK99Rewards);
        }

        emit HarvestPointsOnly(tokenId, to, pending);
    }

    /**
     * @dev Harvest rewards from a position
     */
    function _harvestPosition(uint256 tokenId, address to) internal {
        StakingPosition storage position = _stakingPositions[tokenId];

        // compute position's pending rewards
        uint256 pending = position.amountWithMultiplier.mul(_accRewardsPerShare).div(1e18).sub(
            position.rewardDebt
        );

        // credit points
        if (pending > 0) {
            _superconductor().creditPoints(ownerOf(tokenId), pending.div(1e18));
        }

        // transfer rewards
        if (pending > 0 || position.pendingLK99Rewards > 0) {
            uint256 lk99Amount = pending.add(position.pendingLK99Rewards);

            if ((position.isLocked && !ILK99(address(_lk99)).emissionsOver()) || address(0) == to) {
                position.pendingLK99Rewards = lk99Amount;
            } else {
                position.pendingLK99Rewards = 0;

                // get superconductor capacity
                uint256 currentCapacity = ILK99(address(_lk99)).superconductorCapacity();

                // compute the charged amount
                uint256 chargedAmount = currentCapacity.mul(lk99Amount).div(1000);

                // burn the rest
                ILK99(address(_lk99)).burn(lk99Amount.sub(chargedAmount));

                // send share of LK99 rewards
                chargedAmount = _safeRewardsTransfer(to, chargedAmount);

                // forbidden to harvest if contract has not explicitly confirmed it handle it
                _checkOnNFTHarvest(to, tokenId, chargedAmount);
            }
        }

        emit HarvestPosition(tokenId, to, pending);
    }

    /**
     * @dev Computes new tokenId and mint associated spNFT to "to" address
     */
    function _mintNextTokenId(address to) internal returns (uint256 tokenId) {
        _tokenIds.increment();
        tokenId = _tokenIds.current();
        _safeMint(to, tokenId);
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(address to, uint256 amount) internal returns (uint256) {
        uint256 balance = _lk99.balanceOf(address(this));
        // cap to available balance
        if (amount > balance) {
            amount = balance;
        }

        _lk99.safeTransfer(to, amount);
        return amount;
    }

    function _superconductor() internal view returns (ISuperconductor) {
        return ISuperconductor(IFactionFactory(factory).superconductor());
    }

    /**
     * @dev Handle deposits of tokens with transfer tax
     */
    function _transferSupportingFeeOnTransfer(address user, uint256 amount) internal returns (uint256 receivedAmount) {
        uint256 previousBalance = _lpToken.balanceOf(address(this));

        // send faction pledge to superconductor
        uint256 depositFeesAmount = amount.mul(fees).div(FEES_DENOMINATOR);
        _lpToken.safeTransferFrom(user, address(_superconductor()), depositFeesAmount);
        _superconductor().dispatch();

        _lpToken.safeTransferFrom(user, address(this), amount.sub(depositFeesAmount));
        return _lpToken.balanceOf(address(this)).sub(previousBalance);
    }

    /**
     * @dev updates position's boost multiplier, totalMultiplier, amountWithMultiplier (_lpSupplyWithMultiplier)
     * and rewardDebt without updating lockMultiplier
     */
    function _updateBoostMultiplierInfoAndRewardDebt(StakingPosition storage position) internal {
        uint256 amountWithMultiplier = position.isLocked ? position.amount.mul(LOCK_BOOST_MULTIPLIER) : position.amount;

        // update global supply
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier).add(amountWithMultiplier);
        position.amountWithMultiplier = amountWithMultiplier;

        position.rewardDebt = amountWithMultiplier.mul(_accRewardsPerShare).div(1e18);
    }

    /**
     * @dev Updates rewards states of this pool to be up-to-date
     */
    function _updateFaction() internal {
        // gets allocated rewards from Master and updates
        (uint256 rewards) = master.claimRewards();

        if (rewards > 0) {
            _accRewardsPerShare = _accRewardsPerShare.add(rewards.mul(1e18).div(_lpSupplyWithMultiplier));
        }

        emit FactionUpdated(block.number, _accRewardsPerShare);
    }

    /**
     * @dev Withdraw from a staking position and destroy it
     *
     * _updateFaction() should be executed before calling this
     */
    function _withdrawFromPosition(address nftOwner, uint256 tokenId, uint256 amountToWithdraw) internal {
        require(amountToWithdraw > 0, "withdrawFromPosition: amount cannot be null");

        StakingPosition storage position = _stakingPositions[tokenId];
        require(position.amount >= amountToWithdraw, "invalid");
        require(!position.isLocked || ILK99(address(_lk99)).emissionsOver(), "position is locked");

        _harvestPosition(tokenId, nftOwner);

        // update position
        position.amount = position.amount.sub(amountToWithdraw);

        // update total lp supply
        _lpSupply = _lpSupply.sub(amountToWithdraw);

        if (position.amount == 0) {
            // destroy if now empty
            _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);
            _destroyPosition(tokenId);
        } else {
            _updateBoostMultiplierInfoAndRewardDebt(position);
        }

        _lpToken.safeTransfer(nftOwner, amountToWithdraw);
        emit WithdrawFromPosition(tokenId, amountToWithdraw);
    }
}
