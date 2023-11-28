// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.23;

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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract STZLockTest is Test {
    using Math for uint256;

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
    event AddedRewards(uint256 amount, ISTZLock.RewardType rewardType);
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

    function testUnlock() external lockedSTZ(10 ether) {
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Unlocked(bob, block.timestamp, 10 ether);
        stzLock.unlock(10 ether);
        vm.stopPrank();

        (uint256 timestamp, uint256 amount,) = stzLock.unlockRequests(bob);
        assertEq(timestamp, block.timestamp + 7 days);
        assertEq(amount, 10 ether);
    }

    modifier unlock() {
        vm.startPrank(bob);
        stzLock.unlock(10 ether);
        vm.stopPrank();
        _;
    }

    function testRevertRequestUnlockWhenIsOngoing() external lockedSTZ(10 ether) unlock {
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

    function testReverRedeemWithAntecipatedRedeem() external lockedSTZ(10 ether) unlock {
        vm.startPrank(bob);
        vm.expectRevert(ISTZLock.STZLock__OutOfUnlockWindow.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRevertRedeemWithOutdatedRequest() external lockedSTZ(10 ether) unlock {
        vm.startPrank(bob);
        (uint256 timestamp,,) = stzLock.unlockRequests(bob);
        uint256 unlockWindow = timestamp + stzLock.UNLOCK_WINDOW_PERIOD();
        vm.warp(unlockWindow + 2 hours);
        vm.expectRevert(ISTZLock.STZLock__OutOfUnlockWindow.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRevertRedeemkWhenAmountIsBiggerThanLockedBalance() external lockedSTZ(10 ether) unlock {
        vm.startPrank(bob);
        (uint256 timestamp,,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        vm.expectRevert(ISTZLock.STZLock__UnsufficientLockedBalance.selector);
        stzLock.redeem(11 ether);
        vm.stopPrank();
    }

    function testRevertRedeemWhenAmountIsbiggerThanRequested() external lockedSTZ(10 ether) {
        vm.startPrank(bob);
        stzLock.unlock(9 ether);
        (uint256 timestamp,, bool valid) = stzLock.unlockRequests(bob);
        assertEq(valid, true);

        vm.warp(timestamp + 1 hours);

        vm.expectRevert(ISTZLock.STZLock__AmountExceedsMaxRequestedToUnlock.selector);
        stzLock.redeem(10 ether);
        vm.stopPrank();
    }

    function testRedeem() external lockedSTZ(10 ether) unlock {
        (uint256 timestamp,,) = stzLock.unlockRequests(bob);
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

    function testRevertWhenPaused() external lockedSTZ(10 ether) {
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

    function testOwnerCanUnpause() external lockedSTZ(10 ether) paused {
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

        stzLock.addRewards(amountInSTZ, ISTZLock.RewardType.STZ);
        stzLock.addRewards(amountInWETH, ISTZLock.RewardType.WETH);
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
        emit AddedRewards(amount, ISTZLock.RewardType.STZ);
        stzLock.addRewards(amount, ISTZLock.RewardType.STZ);
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
        emit AddedRewards(amount, ISTZLock.RewardType.WETH);
        stzLock.addRewards(amount, ISTZLock.RewardType.WETH);
        vm.stopPrank();

        uint256 totalRewardsInWETHEnd = stzLock.totalRewardsInWETH();

        assertEq(totalRewardsInWETHEnd, totalRewardsInWETHStart + amount);
    }

    // TEST CALCULATE REWARDS

    function testBobCalculateHisRewards() external addedRewards(10 ether, 0.1 ether) lockedSTZ(10 ether) {
        vm.warp(block.timestamp + 4 days);
        uint256 stzRewardsAfter4Days = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 wethRewardsAfter4Days = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

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

        uint256 bobStzRewards = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 bobWethRewards = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

        uint256 maryStzRewards = stzLock.calculateRewards(mary, ISTZLock.RewardType.STZ);
        uint256 maryWethRewards = stzLock.calculateRewards(mary, ISTZLock.RewardType.WETH);

        uint256 carlosStzRewards = stzLock.calculateRewards(carlos, ISTZLock.RewardType.STZ);
        uint256 carlosWethRewards = stzLock.calculateRewards(carlos, ISTZLock.RewardType.WETH);

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
        stzLock.claimRewards(ISTZLock.RewardType.STZ);

        vm.expectRevert(ISTZLock.STZLock__Rewards_Unnavailable.selector);
        stzLock.claimRewards(ISTZLock.RewardType.WETH);
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
        (, uint256 stzClaimedBefore,,,,) = stzLock.usersRewards(bob);
        vm.expectEmit(true, true, true, true);
        emit Claimed(bob, block.timestamp, stzPerSecond, address(stz));
        stzLock.claimRewards(ISTZLock.RewardType.STZ);
        (uint256 stzLastUpdate, uint256 stzClaimed, uint256 stzEarned,,,) = stzLock.usersRewards(bob);
        assertEq(stzLastUpdate, block.timestamp);
        assertEq(stzEarned, 0);
        assertEq(stzPerSecond, stzClaimed);
        assertTrue(stzClaimed > stzClaimedBefore);

        emit Claimed(bob, block.timestamp, wethPerSecond, address(weth));
        stzLock.claimRewards(ISTZLock.RewardType.WETH);
        vm.stopPrank();

        uint256 stzBalanceEnd = IERC20(address(stz)).balanceOf(bob);
        uint256 wethBalanceEnd = weth.balanceOf(bob);

        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ), 0);
        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH), 0);
        assertEq(stzBalanceEnd, stzPerSecond);
        assertEq(wethBalanceEnd, wethPerSecond);
    }

    function testBobClaimRewardsAfterRedeem()
        external
        addedRewards(1_000 ether, 100 ether)
        lockedSTZ(10 ether)
        unlock
    {
        (uint256 timestamp,,) = stzLock.unlockRequests(bob);
        vm.warp(block.timestamp + timestamp + 1 hours);

        uint256 bobStzRewardsStart = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 bobWethRewardsStart = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), 10 ether);
        stzLock.redeem(10 ether);
        vm.stopPrank();

        uint256 bobStzRewardsEnd = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 bobWethRewardsEnd = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

        assertEq(bobStzRewardsStart, bobStzRewardsEnd);
        assertEq(bobWethRewardsStart, bobWethRewardsEnd);

        vm.startPrank(bob);
        stzLock.claimRewards(ISTZLock.RewardType.STZ);
        stzLock.claimRewards(ISTZLock.RewardType.WETH);
        vm.stopPrank();

        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ), 0);
        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH), 0);
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

        uint256 bobStzRewardsStart = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 bobWethRewardsStart = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

        // WARP SOME DAYS AFTER ENDING LOCK PERIOD
        vm.warp(block.timestamp + 10 days);
        assertTrue(block.timestamp > stzLock.END_STAKING_UNIX_TIME());

        uint256 bobStzRewardsEnd = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);
        uint256 bobWethRewardsEnd = stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH);

        assertTrue(bobStzRewardsEnd >= bobStzRewardsStart);
        assertTrue(bobWethRewardsEnd >= bobWethRewardsStart);

        vm.startPrank(bob);
        stzLock.claimRewards(ISTZLock.RewardType.STZ);
        stzLock.claimRewards(ISTZLock.RewardType.WETH);
        vm.stopPrank();

        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ), 0);
        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.WETH), 0);
    }

    function testFuzzRedeem(uint256 amount) external {
        vm.assume(amount > 0 && amount < IERC20(address(stz)).balanceOf(owner));
        assertTrue(amount < IERC20(address(stz)).balanceOf(owner));

        // OWNER SENDS MONEY TO BOB
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        // BOB LOCKS
        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        stzLock.lock(amount);
        vm.stopPrank();

        assertEq(stzLock.balances(bob), amount);

        // BOB REQUEST UNLOCK
        vm.startPrank(bob);
        stzLock.unlock(amount);
        vm.stopPrank();

        // WARP 7 DAYS OF UNLOCK REQUEST PERIOD
        (uint256 timestamp,,) = stzLock.unlockRequests(bob);
        vm.warp(timestamp + 1 hours);

        // BOB REDEEMS
        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), amount);
        stzLock.redeem(amount);
        vm.stopPrank();

        assertEq(IERC20(address(stz)).balanceOf(bob), amount);
        assertEq(stzLock.balances(bob), 0);
    }

    function testFuzzRewards(uint256 amount) external addedRewards(1000 ether, 100 ether) {
        vm.assume(amount > 0 && amount < IERC20(address(stz)).balanceOf(owner));
        assertTrue(amount < IERC20(address(stz)).balanceOf(owner));

        // OWNER SENDS MONEY TO BOB
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        // BOB LOCKS
        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        stzLock.lock(amount);
        vm.stopPrank();

        assertEq(stzLock.balances(bob), amount);

        uint256 rewards1 = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);

        vm.warp(block.timestamp + 7 days);
        uint256 rewards2 = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);

        vm.warp(block.timestamp + 7 days);
        uint256 rewards3 = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);

        vm.warp(block.timestamp + 7 days);
        uint256 rewards4 = stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ);

        assertTrue(rewards2 > rewards1);
        assertTrue(rewards3 > rewards2);
        assertTrue(rewards4 > rewards3);
        assertEq(IERC20(address(stz)).balanceOf(bob), 0);

        // BOB CLAIM REWARDS
        vm.startPrank(bob);
        stzLock.claimRewards(ISTZLock.RewardType.STZ);
        vm.stopPrank();

        (uint256 stzLastUpdate, uint256 stzClaimed, uint256 stzEarned,,,) = stzLock.usersRewards(bob);
        assertEq(stzLastUpdate, block.timestamp);
        assertEq(stzClaimed, rewards4);
        assertEq(stzEarned, 0);

        assertEq(stzLock.calculateRewards(bob, ISTZLock.RewardType.STZ), 0);
        assertEq(IERC20(address(stz)).balanceOf(bob), rewards4);
    }

    function testFuzzLockedPoints(uint256 amount) external addedRewards(1000 ether, 100 ether) {
        vm.assume(amount > 0 && amount < IERC20(address(stz)).balanceOf(owner));
        assertTrue(amount < IERC20(address(stz)).balanceOf(owner));

        // OWNER SENDS MONEY TO BOB
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        // BOB LOCKS
        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        stzLock.lock(amount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        uint256 lockedPointsStart = stzLock.calculateLockedPoints(bob);
        assertTrue(lockedPointsStart > 0);

        vm.startPrank(bob);
        stzLock.unlock(amount);
        vm.stopPrank();

        (uint256 timestamp,,) = stzLock.unlockRequests(bob);

        vm.warp(timestamp + 1 days);
        uint256 lockedPointsMid = stzLock.calculateLockedPoints(bob);
        assertTrue(lockedPointsMid > lockedPointsStart);

        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), amount);
        stzLock.redeem(amount);

        assertEq(stzLock.calculateLockedPoints(bob), 0);
    }

    function testFuzzLockedPointsAfterLockingPeriodEnds(uint256 amount) external addedRewards(1000 ether, 100 ether) {
        vm.assume(amount > 0 && amount < IERC20(address(stz)).balanceOf(owner));
        assertTrue(amount < IERC20(address(stz)).balanceOf(owner));

        // OWNER SENDS MONEY TO BOB
        vm.startPrank(owner);
        IERC20(address(stz)).approve(owner, amount);
        IERC20(address(stz)).transferFrom(owner, bob, amount);
        vm.stopPrank();

        // BOB LOCKS
        vm.startPrank(bob);
        IERC20(address(stz)).approve(address(stzLock), amount);
        stzLock.lock(amount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        uint256 lockedPointsStart = stzLock.calculateLockedPoints(bob);
        assertTrue(lockedPointsStart > 0);

        vm.warp(block.timestamp + stzLock.END_STAKING_UNIX_TIME() + 1 days);

        vm.startPrank(bob);
        stzLock.unlock(amount);
        vm.stopPrank();

        (uint256 timestamp,,) = stzLock.unlockRequests(bob);

        vm.warp(timestamp + 1 days);
        uint256 lockedPointsMid = stzLock.calculateLockedPoints(bob);
        assertTrue(lockedPointsMid > lockedPointsStart);

        vm.startPrank(bob);
        IERC20(address(str)).approve(address(stzLock), amount);
        stzLock.redeem(amount);

        assertEq(stzLock.calculateLockedPoints(bob), 0);
    }
}
