// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

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

    uint256 public constant LINEAR_LOCK_PERIOD = 7 days;
    uint256 public constant UNLOCK_REQUEST_PERIOD = 7 days;
    uint256 public constant UNLOCK_WINDOW_PERIOD = 3 days;
    uint256 public constant END_STAKING_UNIX_TIME = 365 days;

    uint256 public immutable STZ_REWARDS_PER_SECOND;
    uint256 public immutable WETH_REWARDS_PER_SECOND;

    uint256 public totalRewardsInSTZ;
    uint256 public totalRewardsInWETH;
    uint256 public totalLocked;

    IERC20 public immutable STZ;
    IERC20 public immutable WETH;

    ISTRTokenReceipt public immutable STR;

    mapping(address account => uint256 amount) public balances;
    mapping(address account => uint256 linearLockPeriod) public linearLockPeriods;
    mapping(address account => ISTZLock.UnlockRequest unlockRequest) public unlockRequests;
    mapping(address account => ISTZLock.Rewards userRewards) public usersRewards;

    event Locked(address account, uint256 lockedAt, uint256 amount);
    event Unlocked(address account, uint256 unlockedAt, uint256 amount);
    event Redeemed(address account, uint256 redeemedAt, uint256 amount);
    event Claimed(address account, uint256 claimedAt, uint256 amount, address token);
    event STZAddedAsRewards(uint256 amount);
    event WETHAddedAsRewards(uint256 amount);
    event EmergencyWithdrawal(uint256 amountInSTZ, uint256 amountInWETH);

    constructor(address _STZ, address _STR, address _WETH) Ownable(msg.sender) {
        STZ = IERC20(_STZ);
        WETH = IERC20(_WETH);

        STR = ISTRTokenReceipt(_STR);

        STZ_REWARDS_PER_SECOND = uint256(10 ether) / 86400;
        WETH_REWARDS_PER_SECOND = uint256(0.1 ether) / 86400;
    }

    modifier canLock(uint256 amount) {
        // Amount is lower than permited
        if (amount == 0) revert ISTZLock.STZLock__InsufficientAmountToLock();

        uint256 stzBalance = STZ.balanceOf(msg.sender);
        // User tried to lock more than have
        if (stzBalance < amount) revert ISTZLock.STZLock__UnsufficientBalance();
        _;
    }

    modifier canUnlock(uint256 amount) {
        // User has no amount locked
        if (linearLockPeriods[msg.sender] == 0) revert ISTZLock.STZLock__UnsufficientLockedBalance();
        // User needs to wait linear lock period to unlock
        if (block.timestamp < linearLockPeriods[msg.sender]) revert ISTZLock.STZLock__LockedInLinearPeriod();
        // User already requested for unlock
        if (
            unlockRequests[msg.sender].timestamp > 0
                && block.timestamp <= unlockRequests[msg.sender].timestamp + UNLOCK_REQUEST_PERIOD + UNLOCK_WINDOW_PERIOD
        ) {
            revert ISTZLock.STZLock__RequestForUnlockIsOngoing();
        }
        _;
    }

    modifier canRedeem(uint256 amount) {
        // User didn't requested to unlock yet
        if (unlockRequests[msg.sender].timestamp == 0) revert ISTZLock.STZLock__RequestForUnlockNotFound();
        // Unlock window didn't start yet
        if (block.timestamp < unlockRequests[msg.sender].timestamp + UNLOCK_REQUEST_PERIOD) {
            revert ISTZLock.STZLock__OutOfUnlockWindow();
        }
        // Unlock window is over
        if (block.timestamp > unlockRequests[msg.sender].timestamp + UNLOCK_REQUEST_PERIOD + UNLOCK_WINDOW_PERIOD) {
            revert ISTZLock.STZLock__OutOfUnlockWindow();
        }
        // User has less balance then requested
        if (balances[msg.sender] < amount) revert ISTZLock.STZLock__UnsufficientLockedBalance();
        // User is trying to unlock more than requested
        if (unlockRequests[msg.sender].amount < amount) revert ISTZLock.STZLock__AmountExceedsMaxRequestedToUnlock();
        _;
    }

    function lock(uint256 amount) external whenNotPaused canLock(amount) nonReentrant {
        STZ.safeTransferFrom(msg.sender, address(this), amount);

        if (linearLockPeriods[msg.sender] == 0) linearLockPeriods[msg.sender] = block.timestamp + LINEAR_LOCK_PERIOD;

        updateRewards(msg.sender);
        balances[msg.sender] += amount;
        totalLocked += amount;

        emit Locked(msg.sender, block.timestamp, amount);

        STR.mint(address(this), amount);

        IERC20(address(STR)).safeTransfer(msg.sender, amount);
    }

    function unlock(uint256 amount) external whenNotPaused canUnlock(amount) nonReentrant {
        ISTZLock.UnlockRequest memory unlockRequest = ISTZLock.UnlockRequest(block.timestamp + 7 days, amount);
        unlockRequests[msg.sender] = unlockRequest;
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

    function addSTZAsRewards(uint256 amount) external whenNotPaused nonReentrant {
        if (amount > 0) {
            totalRewardsInSTZ += amount;
            emit STZAddedAsRewards(amount);

            STZ.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function addWETHAsRewards(uint256 amount) external whenNotPaused nonReentrant {
        if (amount > 0) {
            totalRewardsInWETH += amount;
            emit WETHAddedAsRewards(amount);

            WETH.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function claimSTZRewards(address account) public whenNotPaused nonReentrant {
        uint256 _totalRewards = totalRewardsInSTZ;
        if (_totalRewards > 0) {
            uint256 stzRewards = calculateSTZRewards(account);
            if (stzRewards == 0 || _totalRewards < stzRewards) revert ISTZLock.STZLock__Rewards_Unnavailable();

            ISTZLock.Rewards storage userRewards = usersRewards[account];
            userRewards.STZ_earned = 0;
            userRewards.STZ_claimed += stzRewards;
            userRewards.STZ_lastUpdate = block.timestamp;

            totalRewardsInSTZ -= stzRewards;
            emit Claimed(account, block.timestamp, stzRewards, address(STZ));

            STZ.safeTransfer(account, stzRewards);
        }
    }

    function claimWETHRewards(address account) public whenNotPaused nonReentrant {
        uint256 _totalRewards = totalRewardsInWETH;
        if (_totalRewards > 0) {
            uint256 wethRewards = calculateWETHRewards(account);
            if (wethRewards == 0 || _totalRewards < wethRewards) revert ISTZLock.STZLock__Rewards_Unnavailable();

            ISTZLock.Rewards storage userRewards = usersRewards[account];
            userRewards.WETH_earned = 0;
            userRewards.WETH_claimed += wethRewards;
            userRewards.WETH_lastUpdate = block.timestamp;

            totalRewardsInWETH -= wethRewards;
            emit Claimed(account, block.timestamp, wethRewards, address(WETH));

            WETH.safeTransfer(account, wethRewards);
        }
    }

    function calculateSTZRewards(address account) public view returns (uint256) {
        ISTZLock.Rewards memory userRewards = usersRewards[account];
        uint256 elapsedTime;

        if (block.timestamp > END_STAKING_UNIX_TIME && END_STAKING_UNIX_TIME > userRewards.STZ_lastUpdate) {
            elapsedTime = END_STAKING_UNIX_TIME - userRewards.STZ_lastUpdate;
        } else if (block.timestamp > userRewards.STZ_lastUpdate) {
            elapsedTime = block.timestamp - userRewards.STZ_lastUpdate;
        }

        uint256 lockedAmount = balances[account];
        uint256 accumulatedRewards = userRewards.STZ_earned;

        if (totalRewardsInSTZ == 0 || lockedAmount == 0 || elapsedTime == 0) {
            return accumulatedRewards;
        }

        uint256 PRECISION = 1e24; // Define the precision scaling factor
        uint256 rewardsPerToken = elapsedTime * STZ_REWARDS_PER_SECOND * PRECISION / totalLocked;
        uint256 newRewards = lockedAmount * rewardsPerToken / PRECISION;
        uint256 rewards = accumulatedRewards + newRewards;

        return rewards;
    }

    function calculateWETHRewards(address account) public view returns (uint256) {
        ISTZLock.Rewards memory userRewards = usersRewards[account];
        uint256 elapsedTime;

        if (block.timestamp > END_STAKING_UNIX_TIME && END_STAKING_UNIX_TIME > userRewards.WETH_lastUpdate) {
            elapsedTime = END_STAKING_UNIX_TIME - userRewards.WETH_lastUpdate;
        } else if (block.timestamp > userRewards.WETH_lastUpdate) {
            elapsedTime = block.timestamp - userRewards.WETH_lastUpdate;
        }

        uint256 lockedAmount = balances[account];
        uint256 accumulatedRewards = userRewards.WETH_earned;

        if (totalRewardsInWETH == 0 || lockedAmount == 0 || elapsedTime == 0) {
            return accumulatedRewards;
        }

        uint256 PRECISION = 1e24; // Define the precision scaling factor
        uint256 rewardsPerToken = ((elapsedTime * WETH_REWARDS_PER_SECOND * PRECISION) / totalLocked);
        uint256 newRewards = lockedAmount * rewardsPerToken / PRECISION;
        uint256 rewards = accumulatedRewards + newRewards;

        return rewards;
    }

    function updateRewards(address account) internal {
        ISTZLock.Rewards storage userRewards = usersRewards[account];
        userRewards.STZ_earned = calculateSTZRewards(account);
        userRewards.STZ_lastUpdate = block.timestamp;

        userRewards.WETH_earned = calculateWETHRewards(account);
        userRewards.WETH_lastUpdate = block.timestamp;
    }
}
