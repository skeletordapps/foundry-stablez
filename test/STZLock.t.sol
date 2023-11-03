// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {DeploySTZLock} from "../script/DeploySTZLock.sol";
import {STZToken} from "../src/STZToken.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";
import {STZLock} from "../src/STZLock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {console2} from "forge-std/console2.sol";

contract STZLockTest is Test {
    DeploySTZLock deployer;
    STZToken stzToken;
    STRTokenReceipt strTokenReceipt;
    STZLock stzLock;
    address owner;
    address bob;

    function setUp() public virtual {
        deployer = new DeploySTZLock();
        (stzToken, strTokenReceipt, stzLock) = deployer.run();
        owner = stzToken.owner();

        vm.startPrank(owner);
        stzToken.grantMintRole(address(stzLock));
        stzToken.grantBurnRole(address(stzLock));
        strTokenReceipt.grantMintRole(address(stzLock));
        strTokenReceipt.grantBurnRole(address(stzLock));

        stzToken.mint(owner, 100 ether);

        vm.stopPrank();

        bob = vm.addr(1);
        vm.label(bob, "bob");
    }

    function testConstructor() public {
        assertEq(stzToken.owner(), owner);
        assertEq(strTokenReceipt.owner(), owner);
        assertEq(stzLock.owner(), owner);
    }

    function testLock() external {
        vm.startPrank(owner);
        ERC20(address(stzToken)).approve(owner, 10 ether);
        ERC20(address(stzToken)).transferFrom(owner, bob, 10 ether);
        vm.stopPrank();

        assertEq(ERC20(address(stzToken)).balanceOf(owner), 90 ether);
        assertEq(ERC20(address(stzToken)).balanceOf(bob), 10 ether);

        vm.startPrank(bob);
        ERC20(address(stzToken)).approve(address(stzLock), 10 ether);
        stzLock.lock(10 ether);
        vm.stopPrank();

        assertEq(stzLock.locks(bob), 10 ether);
        assertEq(ERC20(address(stzToken)).balanceOf(bob), 0);
        assertEq(ERC20(address(strTokenReceipt)).balanceOf(bob), 10 ether);
    }

    function testUnlock() external {
        vm.startPrank(owner);
        ERC20(address(stzToken)).approve(owner, 10 ether);
        ERC20(address(stzToken)).transferFrom(owner, bob, 10 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        ERC20(address(stzToken)).approve(address(stzLock), 10 ether);
        stzLock.lock(10 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);
        vm.startPrank(bob);
        ERC20(address(strTokenReceipt)).approve(address(stzLock), 10 ether);
        stzLock.unlock(10 ether);
        vm.stopPrank();

        assertEq(stzLock.locks(bob), 0);
        assertEq(ERC20(address(stzToken)).balanceOf(bob), 10 ether);
        assertEq(ERC20(address(strTokenReceipt)).balanceOf(bob), 0);
    }
}
