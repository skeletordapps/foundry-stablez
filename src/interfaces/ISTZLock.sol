// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ISTZLock {
    struct UserPoints {
        uint256 lastUpdate;
        uint256 accumulated;
    }

    struct UnlockRequest {
        uint256 timestamp;
        uint256 amount;
    }

    struct Rewards {
        uint256 STZ_lastUpdate;
        uint256 STZ_claimed; // only for frontend purpouses
        uint256 STZ_earned;
        uint256 WETH_lastUpdate;
        uint256 WETH_claimed; // only for frontend purpouses
        uint256 WETH_earned;
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
