// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ISTRTokenReceipt} from "../src/interfaces/ISTRTokenReceipt.sol";
import {ISTZLock} from "../src/interfaces/ISTZLock.sol";

import {console2} from "forge-std/console2.sol";

contract STZLock is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant UNLOCK_REQUEST_PERIOD = 7 days;
    uint256 public constant UNLOCK_WINDOW_PERIOD = 3 days;
    uint256 public constant END_STAKING_UNIX_TIME = 365 days;

    uint256 public immutable STZ_REWARDS_PER_SECOND;
    uint256 public immutable WETH_REWARDS_PER_SECOND;
    uint256 public immutable LPS_REWARDS_PER_SECOND;

    uint256 public totalRewardsInSTZ;
    uint256 public totalRewardsInWETH;
    uint256 public totalLocked;

    IERC20 public immutable STZ;
    IERC20 public immutable WETH;

    ISTRTokenReceipt public immutable STR;

    mapping(address account => uint256 amount) public balances;
    mapping(address account => ISTZLock.UnlockRequest unlockRequest) public unlockRequests;
    mapping(address account => ISTZLock.Rewards userRewards) public usersRewards;

    event Locked(address account, uint256 lockedAt, uint256 amount);
    event Unlocked(address account, uint256 unlockedAt, uint256 amount);
    event Redeemed(address account, uint256 redeemedAt, uint256 amount);
    event Claimed(address account, uint256 claimedAt, uint256 amount, address token);
    event AddedRewards(uint256 amount, ISTZLock.RewardType rewardType);
    event EmergencyWithdrawal(uint256 amountInSTZ, uint256 amountInWETH);

    constructor(address _STZ, address _STR, address _WETH) Ownable(msg.sender) {
        STZ = IERC20(_STZ);
        WETH = IERC20(_WETH);

        STR = ISTRTokenReceipt(_STR);

        STZ_REWARDS_PER_SECOND = uint256(10 ether) / 86400;
        WETH_REWARDS_PER_SECOND = uint256(0.1 ether) / 86400;
    }

    modifier canLock(uint256 amount) {
        // Amount is zero
        if (amount == 0) revert ISTZLock.STZLock__InsufficientAmountToLock();

        // User tried to lock more than have
        if (STZ.balanceOf(msg.sender) < amount) revert ISTZLock.STZLock__UnsufficientBalance();
        _;
    }

    modifier canUnlock(uint256 amount) {
        // User has no amount locked
        if (amount > balances[msg.sender]) revert ISTZLock.STZLock__UnsufficientLockedBalance();

        // User already requested for unlock
        if (unlockRequests[msg.sender].valid) revert ISTZLock.STZLock__RequestForUnlockIsOngoing();
        _;
    }

    modifier canRedeem(uint256 amount) {
        // User didn't requested to unlock yet
        if (!unlockRequests[msg.sender].valid) revert ISTZLock.STZLock__RequestForUnlockNotFound();
        // Unlock window didn't start yet
        if (block.timestamp < unlockRequests[msg.sender].timestamp) revert ISTZLock.STZLock__OutOfUnlockWindow();
        // Unlock window is over
        if (block.timestamp > unlockRequests[msg.sender].timestamp + UNLOCK_WINDOW_PERIOD) {
            unlockRequests[msg.sender].valid = false; // Update unlock request to invalid.
            revert ISTZLock.STZLock__OutOfUnlockWindow();
        }
        // User has less balance then requested
        if (amount > balances[msg.sender]) revert ISTZLock.STZLock__UnsufficientLockedBalance();
        // User is trying to unlock more than requested
        if (amount > unlockRequests[msg.sender].amount) revert ISTZLock.STZLock__AmountExceedsMaxRequestedToUnlock();
        _;
    }

    function lock(uint256 amount) external whenNotPaused canLock(amount) nonReentrant {
        STZ.safeTransferFrom(msg.sender, address(this), amount);

        updateRewards(msg.sender);
        balances[msg.sender] += amount;
        totalLocked += amount;

        emit Locked(msg.sender, block.timestamp, amount);

        STR.mint(address(this), amount);

        IERC20(address(STR)).safeTransfer(msg.sender, amount);
    }

    function unlock(uint256 amount) external whenNotPaused canUnlock(amount) nonReentrant {
        unlockRequests[msg.sender] = ISTZLock.UnlockRequest(block.timestamp + 7 days, amount, true);
        emit Unlocked(msg.sender, block.timestamp, amount);
    }

    function redeem(uint256 amount) external whenNotPaused canRedeem(amount) nonReentrant {
        IERC20(address(STR)).safeTransferFrom(msg.sender, address(this), amount);

        updateRewards(msg.sender);

        balances[msg.sender] -= amount;
        totalLocked -= amount;

        emit Redeemed(msg.sender, block.timestamp, amount);

        STR.burn(address(this), amount);
        STZ.safeTransfer(msg.sender, amount);
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 balanceInSTZ = STZ.balanceOf(address(this));
        uint256 balanceInWETH = WETH.balanceOf(address(this));
        STZ.safeTransfer(owner(), balanceInSTZ);
        WETH.safeTransfer(owner(), balanceInWETH);

        emit EmergencyWithdrawal(balanceInSTZ, balanceInWETH);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addRewards(uint256 amount, ISTZLock.RewardType rewardType) external whenNotPaused nonReentrant {
        if (amount > 0) {
            if (rewardType == ISTZLock.RewardType.STZ) {
                STZ.safeTransferFrom(msg.sender, address(this), amount);
                totalRewardsInSTZ += amount;
            } else {
                WETH.safeTransferFrom(msg.sender, address(this), amount);
                totalRewardsInWETH += amount;
            }
            emit AddedRewards(amount, rewardType);
        }
    }

    function claimRewards(ISTZLock.RewardType rewardType) public whenNotPaused nonReentrant {
        uint256 _totalRewards = rewardType == ISTZLock.RewardType.STZ ? totalRewardsInSTZ : totalRewardsInWETH;

        if (_totalRewards > 0) {
            uint256 rewards = calculateRewards(msg.sender, rewardType);
            if (rewards == 0 || _totalRewards < rewards) revert ISTZLock.STZLock__Rewards_Unnavailable();

            ISTZLock.Rewards memory userRewards = usersRewards[msg.sender];

            if (rewardType == ISTZLock.RewardType.STZ) {
                userRewards.stzEarned = 0;
                userRewards.stzClaimed += rewards;
                userRewards.stzLastUpdate = block.timestamp;
                usersRewards[msg.sender] = userRewards;

                totalRewardsInSTZ -= rewards;
                emit Claimed(msg.sender, block.timestamp, rewards, address(STZ));

                STZ.safeTransfer(msg.sender, rewards);
            } else {
                userRewards.wethEarned = 0;
                userRewards.wethClaimed += rewards;
                userRewards.wethLastUpdate = block.timestamp;
                usersRewards[msg.sender] = userRewards;

                totalRewardsInWETH -= rewards;
                emit Claimed(msg.sender, block.timestamp, rewards, address(WETH));

                WETH.safeTransfer(msg.sender, rewards);
            }
        }
    }

    function calculateRewards(address account, ISTZLock.RewardType rewardType) public view returns (uint256) {
        ISTZLock.Rewards memory userRewards = usersRewards[account];

        uint256 elapsedTime;
        uint256 rewardsPerSecond;
        uint256 rewardsLastUpdate;
        uint256 accumulatedRewards;

        if (rewardType == ISTZLock.RewardType.STZ) {
            rewardsPerSecond = STZ_REWARDS_PER_SECOND;
            rewardsLastUpdate = userRewards.stzLastUpdate;
            accumulatedRewards = userRewards.stzEarned;
        } else {
            rewardsPerSecond = WETH_REWARDS_PER_SECOND;
            rewardsLastUpdate = userRewards.wethLastUpdate;
            accumulatedRewards = userRewards.wethEarned;
        }

        if (block.timestamp > rewardsLastUpdate) {
            elapsedTime = (block.timestamp > END_STAKING_UNIX_TIME)
                ? END_STAKING_UNIX_TIME - rewardsLastUpdate
                : block.timestamp - rewardsLastUpdate;
        }

        uint256 lockedAmount = balances[account];

        if (totalLocked == 0 || lockedAmount == 0 || elapsedTime == 0) return accumulatedRewards;

        uint256 rewardsPerToken = (elapsedTime * rewardsPerSecond * 1e24) / totalLocked;
        uint256 newRewards = (lockedAmount * rewardsPerToken) / 1e24;

        return accumulatedRewards + newRewards;
    }

    function updateRewards(address account) internal {
        ISTZLock.Rewards memory userRewards = usersRewards[account];
        userRewards.stzEarned = calculateRewards(account, ISTZLock.RewardType.STZ);
        userRewards.stzLastUpdate = block.timestamp;
        userRewards.wethEarned = calculateRewards(account, ISTZLock.RewardType.WETH);
        userRewards.wethLastUpdate = block.timestamp;
        usersRewards[account] = userRewards;
    }
}
