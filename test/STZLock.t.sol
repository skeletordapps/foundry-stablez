// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {DeploySTZLock} from "../script/DeploySTZLock.sol";
import {STZToken} from "../src/STZToken.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";
import {ISTZLock} from "../src/interfaces/ISTZLock.sol";
import {STZLock} from "../src/STZLock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {console2} from "forge-std/console2.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract STZLockTest is Test {
    DeploySTZLock deployer;
    STZToken stz;
    STRTokenReceipt str;
    IERC20 weth;
    STZLock stzLock;
    address owner;
    address bob;
    address mary;
    address carlos;

    event Locked(address account, uint256 lockedAt, uint256 amount);
    event Unlocked(address account, uint256 unlockedAt, uint256 amount);
    event Redeemed(address account, uint256 redeemedAt, uint256 amount);
    event Claimed(address account, uint256 claimedAt, uint256 amount, address token);
    event STZAddedAsRewards(uint256 amount);
    event WETHAddedAsRewards(uint256 amount);
    event EmergencyWithdrawal(uint256 amountInSTZ, uint256 amountInWETH);

    function setUp() public virtual {
        deployer = new DeploySTZLock();
        (stz, str, weth, stzLock) = deployer.run();
        owner = stz.owner();

        vm.startPrank(owner);
        str.grantMintRole(address(stzLock));
        str.grantBurnRole(address(stzLock));
        vm.stopPrank();

        bob = vm.addr(1);
        vm.label(bob, "bob");
        mary = vm.addr(2);
        vm.label(mary, "mary");
        carlos = vm.addr(3);
        vm.label(carlos, "carlos");

        deal(address(weth), owner, 100 ether);
    }

    function testConstructor() public {
        assertEq(stz.owner(), owner);
        assertEq(str.owner(), owner);
        assertEq(stzLock.owner(), owner);
    }

    // LOCK TESTS

    function testRevertLockWithLessThenMinPermited() external {
        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), 0);
        vm.expectRevert(ISTZLock.STZLock__InsufficientAmountToLock.selector);
        stzLock.lock(0);
        vm.stopPrank();
    }

    function testRevertLockWithLowerBalanceThanAmount() external {
        uint256 amount = 10 ether;

        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        vm.expectRevert(ISTZLock.STZLock__UnsufficientBalance.selector);
        stzLock.lock(amount + 1 ether);
        vm.stopPrank();
    }

    function testLock() external {
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, 10 ether);
        IERC20(address(stz)).transferFrom(owner, bob, 10 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), 10 ether);
        stzLock.lock(10 ether);
        vm.stopPrank();

        assertEq(stzLock.balances(bob), 10 ether);
        assertEq(IERC20(address(stz)).balanceOf(address(stzLock)), 10 ether);
        assertEq(IERC20(address(stz)).balanceOf(bob), 0);
        assertEq(IERC20(address(str)).balanceOf(bob), 10 ether);
    }

    // TEST UNLOCK

    function testRevertUnlockWhenHasNoLockedYet() external {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__UnsufficientLockedBalance.selector);
        stzLock.unlock(10 ether);
        vm.stopPrank();
    }

    modifier lockedSTZ(uint256 amount) {
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        vm.expectEmit(true, true, true, true);
        emit Locked(bob, block.timestamp, amount);
        stzLock.lock(amount);
        vm.stopPrank();
        _;
    }

    function testRevertUnlockWhenInLinearUnlockPeriod() external lockedSTZ(10 ether) {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__LockedInLinearPeriod.selector);
        stzLock.unlock(10 ether);
        vm.stopPrank();
    }

    function testUnlock() external lockedSTZ(10 ether) {
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Unlocked(bob, block.timestamp, 10 ether);
        stzLock.unlock(10 ether);
        vm.stopPrank();

        (uint256 timestamp, uint256 amount) = stzLock.unlockRequests(bob);
        assertEq(timestamp, block.timestamp + 7 days);
        assertEq(amount, 10 ether);
    }

    modifier linearUnlockPeriodPassed() {
        vm.warp(block.timestamp + 7 days);
        _;
    }

    modifier unlock() {
        vm.startPrank(bob);
        stzLock.unlock(10 ether);
        vm.stopPrank();
        _;
    }

    function testRevertRequestUnlockWhenIsOngoing() external lockedSTZ(10 ether) linearUnlockPeriodPassed unlock {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__RequestForUnlockIsOngoing.selector);
        stzLock.unlock(10 ether);
        vm.stopPrank();
    }

    // TEST REDEEM

    function testRevertRedeemWhenHasNoUnlocked() external lockedSTZ(10 ether) {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__RequestForUnlockNotFound.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testReverRedeemWithAntecipatedRedeem() external lockedSTZ(10 ether) linearUnlockPeriodPassed unlock {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__OutOfUnlockWindow.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRevertRedeemWithOutdatedRequest() external lockedSTZ(10 ether) linearUnlockPeriodPassed unlock {
        vm.startPrank(bob);
        (uint256 timestamp,) = stzLock.unlockRequests(bob);
        uint256 unlockWindow = timestamp + stzLock.UNLOCK_WINDOW_PERIOD();
        vm.warp(block.timestamp + unlockWindow + 2 hours);
        vm.expectRevert(ISTZLock.STZLock__OutOfUnlockWindow.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRevertRedeemkWhenAmountIsBiggerThanLockedBalance()
        external
        lockedSTZ(10 ether)
        linearUnlockPeriodPassed
        unlock
    {
        vm.startPrank(bob);
        (uint256 timestamp,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        vm.expectRevert(ISTZLock.STZLock__UnsufficientLockedBalance.selector);
        stzLock.redeem(11 ether);
        vm.stopPrank();
    }

    function testRevertRedeemWhenAmountIsbiggerThanRequested() external lockedSTZ(10 ether) linearUnlockPeriodPassed {
        vm.startPrank(bob);
        stzLock.unlock(9 ether);
        (uint256 timestamp,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        vm.expectRevert(ISTZLock.STZLock__AmountExceedsMaxRequestedToUnlock.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRedeem() external lockedSTZ(10 ether) linearUnlockPeriodPassed unlock {
        (uint256 timestamp,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), 10 ether);
        vm.expectEmit(true, true, true, true);
        emit Redeemed(bob, block.timestamp, 10 ether);
        stzLock.redeem(10 ether);
        vm.stopPrank();

        assertEq(stzLock.balances(bob), 0);
        assertEq(IERC20(address(stz)).balanceOf(bob), 10 ether);
        assertEq(IERC20(address(str)).balanceOf(bob), 0 ether);
    }

    // TEST PAUSE & UNPAUSE

    function testRevertWhenPaused() external lockedSTZ(10 ether) linearUnlockPeriodPassed {
        vm.startPrank(owner);
        stzLock.pause();
        assertEq(stzLock.paused(), true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stzLock.unlock(10 ether);
        vm.stopPrank();
    }

    modifier paused() {
        vm.startPrank(owner);
        stzLock.pause();
        vm.stopPrank();
        _;
    }

    function testOwnerCanUnpause() external lockedSTZ(10 ether) linearUnlockPeriodPassed paused {
        vm.startPrank(owner);
        stzLock.unpause();
        vm.stopPrank();

        assertEq(stzLock.paused(), false);
    }

    // TEST EMERGENCY WITHDRAW

    function testRevertEmergencyWithdrawWhenIsNotTheOwner() external lockedSTZ(10 ether) {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        stzLock.emergencyWithdraw();
        vm.stopPrank();
    }

    modifier addedRewards(uint256 amountInSTZ, uint256 amountInWETH) {
        vm.startPrank(owner);
        IERC20(address(stz)).approve(address(stzLock), amountInSTZ);
        weth.approve(address(stzLock), amountInWETH);

        stzLock.addSTZAsRewards(amountInSTZ);
        stzLock.addWETHAsRewards(amountInWETH);
        vm.stopPrank();
        _;
    }

    function testOwnerCanEmergencyWithdraw() external addedRewards(10 ether, 0.1 ether) lockedSTZ(10 ether) {
        uint256 contractBalanceInSTZStart = IERC20(address(stz)).balanceOf(address(stzLock));
        uint256 contractBalanceInWETHStart = weth.balanceOf(address(stzLock));

        uint256 ownerBalanceInSTZStart = IERC20(address(stz)).balanceOf(owner);
        uint256 ownerBalanceInWETHStart = weth.balanceOf(owner);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawal(contractBalanceInSTZStart, contractBalanceInWETHStart);
        stzLock.emergencyWithdraw();
        vm.stopPrank();
        uint256 contractBalanceInSTZEnd = IERC20(address(stz)).balanceOf(address(stzLock));
        uint256 contractBalanceInWETHEnd = weth.balanceOf(address(stzLock));

        uint256 ownerBalanceInSTZEnd = IERC20(address(stz)).balanceOf(owner);
        uint256 ownerBalanceInWETHEnd = weth.balanceOf(owner);

        assertEq(contractBalanceInSTZEnd, 0);
        assertEq(contractBalanceInWETHEnd, 0);
        assertEq(ownerBalanceInSTZEnd, ownerBalanceInSTZStart + contractBalanceInSTZStart);
        assertEq(ownerBalanceInWETHEnd, ownerBalanceInWETHStart + contractBalanceInWETHStart);
    }

    // TEST ADDING REWARDS

    function testAddSTZAsRewards() external {
        uint256 amount = 10 ether;
        uint256 totalRewardsInSTZStart = stzLock.totalRewardsInSTZ();

        vm.startPrank(owner);
        IERC20(address(stz)).approve(address(stzLock), amount);
        vm.expectEmit(true, true, true, true);
        emit STZAddedAsRewards(amount);
        stzLock.addSTZAsRewards(amount);
        vm.stopPrank();

        uint256 totalRewardsInSTZEnd = stzLock.totalRewardsInSTZ();

        assertEq(totalRewardsInSTZEnd, totalRewardsInSTZStart + amount);
    }

    function testAddWETHAsRewards() external {
        uint256 amount = 10 ether;
        uint256 totalRewardsInWETHStart = stzLock.totalRewardsInWETH();

        vm.startPrank(owner);
        weth.approve(address(stzLock), amount);
        vm.expectEmit(true, true, true, true);
        emit WETHAddedAsRewards(amount);
        stzLock.addWETHAsRewards(amount);
        vm.stopPrank();

        uint256 totalRewardsInWETHEnd = stzLock.totalRewardsInWETH();

        assertEq(totalRewardsInWETHEnd, totalRewardsInWETHStart + amount);
    }

    // TEST CALCULATE REWARDS

    function testBobCalculateHisRewards() external addedRewards(10 ether, 0.1 ether) lockedSTZ(10 ether) {
        vm.warp(block.timestamp + 4 days);
        uint256 stzRewardsAfter4Days = stzLock.calculateSTZRewards(bob);
        uint256 wethRewardsAfter4Days = stzLock.calculateWETHRewards(bob);

        assertTrue(stzRewardsAfter4Days > 30 ether && stzRewardsAfter4Days <= 40 ether);
        assertTrue(wethRewardsAfter4Days > 0.3 ether && wethRewardsAfter4Days <= 0.4 ether);
    }

    modifier lockedSTZForAccount(address account, uint256 lockedAmount) {
        vm.assume(lockedAmount > 0 && lockedAmount < 30 ether);

        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, lockedAmount);
        IERC20(address(stz)).transferFrom(owner, account, lockedAmount);
        vm.stopPrank();

        vm.startPrank(account);
        IERC20(address(stz)).approve(address(stzLock), lockedAmount);
        stzLock.lock(lockedAmount);
        vm.stopPrank();
        _;
    }

    function testManyAccountsCanCheckRewards()
        external
        addedRewards(10 ether, 0.1 ether)
        lockedSTZForAccount(bob, 10 ether)
        lockedSTZForAccount(mary, 10 ether)
        lockedSTZForAccount(carlos, 10 ether)
    {
        vm.warp(block.timestamp + 4 days);
        uint256 stzPerSecond = stzLock.STZ_REWARDS_PER_SECOND() * 4 days / 3;
        uint256 wethPerSecond = stzLock.WETH_REWARDS_PER_SECOND() * 4 days / 3;

        uint256 bobStzRewards = stzLock.calculateSTZRewards(bob);
        uint256 bobWethRewards = stzLock.calculateWETHRewards(bob);

        uint256 maryStzRewards = stzLock.calculateSTZRewards(mary);
        uint256 maryWethRewards = stzLock.calculateWETHRewards(mary);

        uint256 carlosStzRewards = stzLock.calculateSTZRewards(carlos);
        uint256 carlosWethRewards = stzLock.calculateWETHRewards(carlos);

        assertTrue(bobStzRewards > stzPerSecond / 2 && bobStzRewards <= stzPerSecond);
        assertTrue(maryStzRewards > stzPerSecond / 2 && maryStzRewards <= stzPerSecond);
        assertTrue(carlosStzRewards > stzPerSecond / 2 && carlosStzRewards <= stzPerSecond);

        assertTrue(bobWethRewards > wethPerSecond / 2 && bobWethRewards <= wethPerSecond);
        assertTrue(maryWethRewards > wethPerSecond / 2 && maryWethRewards <= wethPerSecond);
        assertTrue(carlosWethRewards > wethPerSecond / 2 && carlosWethRewards <= wethPerSecond);
    }

    // TEST CLAIM REWARDS

    function testRevertWhenAvailableRewardsAreLessThanAccrued()
        external
        addedRewards(10 ether, 0.1 ether)
        lockedSTZ(10 ether)
    {
        vm.warp(block.timestamp + 4 days);

        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__Rewards_Unnavailable.selector);
        stzLock.claimSTZRewards(bob);

        vm.expectRevert(ISTZLock.STZLock__Rewards_Unnavailable.selector);
        stzLock.claimWETHRewards(bob);
        vm.stopPrank();
    }

    function testBobClaimRewards() external addedRewards(40 ether, 0.4 ether) lockedSTZ(10 ether) {
        uint256 stzBalanceStart = IERC20(address(stz)).balanceOf(bob);
        uint256 wethBalanceStart = weth.balanceOf(bob);

        assertEq(stzBalanceStart, 0);
        assertEq(wethBalanceStart, 0);

        vm.warp(block.timestamp + 4 days);
        uint256 stzPerSecond = stzLock.STZ_REWARDS_PER_SECOND() * 4 days;
        uint256 wethPerSecond = stzLock.WETH_REWARDS_PER_SECOND() * 4 days;

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Claimed(bob, block.timestamp, stzPerSecond, address(stz));
        stzLock.claimSTZRewards(bob);
        emit Claimed(bob, block.timestamp, wethPerSecond, address(weth));
        stzLock.claimWETHRewards(bob);
        vm.stopPrank();

        uint256 stzBalanceEnd = IERC20(address(stz)).balanceOf(bob);
        uint256 wethBalanceEnd = weth.balanceOf(bob);

        assertEq(stzLock.calculateSTZRewards(bob), 0);
        assertEq(stzLock.calculateWETHRewards(bob), 0);
        assertEq(stzBalanceEnd, stzPerSecond);
        assertEq(wethBalanceEnd, wethPerSecond);
    }

    function testBobClaimRewardsAfterRedeem()
        external
        addedRewards(1_000 ether, 100 ether)
        lockedSTZ(10 ether)
        linearUnlockPeriodPassed
        unlock
    {
        (uint256 timestamp,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        uint256 bobStzRewardsStart = stzLock.calculateSTZRewards(bob);
        uint256 bobWethRewardsStart = stzLock.calculateWETHRewards(bob);

        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), 10 ether);
        stzLock.redeem(10 ether);
        vm.stopPrank();

        uint256 bobStzRewardsEnd = stzLock.calculateSTZRewards(bob);
        uint256 bobWethRewardsEnd = stzLock.calculateWETHRewards(bob);

        assertEq(bobStzRewardsStart, bobStzRewardsEnd);
        assertEq(bobWethRewardsStart, bobWethRewardsEnd);

        vm.startPrank(bob);
        stzLock.claimSTZRewards(bob);
        stzLock.claimWETHRewards(bob);
        vm.stopPrank();

        assertEq(stzLock.calculateSTZRewards(bob), 0);
        assertEq(stzLock.calculateWETHRewards(bob), 0);
    }

    function testBobClaimRewardsAfterLockPeriod() external addedRewards(1_000 ether, 100 ether) {
        // WARP 2 DAYS BEFORE ENDING LOCK PERIOD
        vm.warp(block.timestamp + stzLock.END_STAKING_UNIX_TIME() - 2 days);

        // LOCK
        uint256 amount = 10 ether;
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        stzLock.lock(amount);
        vm.warp(block.timestamp + 7 days); // WARP LINEAR LOCK PERIOD
        stzLock.unlock(10 ether); // REQUEST UNLOCK
        vm.stopPrank();

        uint256 bobStzRewardsStart = stzLock.calculateSTZRewards(bob);
        uint256 bobWethRewardsStart = stzLock.calculateWETHRewards(bob);

        // WARP SOME DAYS AFTER ENDING LOCK PERIOD
        vm.warp(block.timestamp + 10 days);
        assertTrue(block.timestamp > stzLock.END_STAKING_UNIX_TIME());

        uint256 bobStzRewardsEnd = stzLock.calculateSTZRewards(bob);
        uint256 bobWethRewardsEnd = stzLock.calculateWETHRewards(bob);

        assertTrue(bobStzRewardsEnd >= bobStzRewardsStart);
        assertTrue(bobWethRewardsEnd >= bobWethRewardsStart);

        vm.startPrank(bob);
        stzLock.claimSTZRewards(bob);
        stzLock.claimWETHRewards(bob);
        vm.stopPrank();

        assertEq(stzLock.calculateSTZRewards(bob), 0);
        assertEq(stzLock.calculateWETHRewards(bob), 0);
    }
}
