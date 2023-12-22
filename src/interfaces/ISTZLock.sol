// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

interface ISTZLock {
    struct UnlockRequest {
        uint256 timestamp;
        uint256 amount;
        bool valid;
    }

    struct Rewards {
        uint256 stzLastUpdate;
        uint256 stzClaimed; // only for frontend purpouses
        uint256 stzEarned;
        uint256 wethLastUpdate;
        uint256 wethClaimed; // only for frontend purpouses
        uint256 wethEarned;
    }

    error STZLock__UnsufficientBalance();
    error STZLock__InsufficientAmountToLock();
    error STZLock__UnsufficientLockedBalance();
    error STZLock__LockedInLinearPeriod();
    error STZLock__RequestForUnlockIsOngoing();
    error STZLock__OutOfUnlockWindow();
    error STZLock__RequestForUnlockNotFound();
    error STZLock__AmountExceedsMaxRequestedToUnlock();
    error STZLock__Rewards_Unnavailable();
}
