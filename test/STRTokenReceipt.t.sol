// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {DeploySTRTokenReceipt} from "../script/DeploySTRTokenReceipt.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract STRTokenReceiptTest is Test {
    DeploySTRTokenReceipt deployer;
    STRTokenReceipt strTokenReceipt;
    address owner;
    address bob;

    function setUp() public virtual {
        deployer = new DeploySTRTokenReceipt();
        strTokenReceipt = deployer.run();
        owner = strTokenReceipt.owner();
        bob = vm.addr(1);
        vm.label(bob, "bob");
    }

    function testRevertMint() external {
        vm.startPrank(bob);
        bytes32 MINTER_STR_ROLE = keccak256("MINTER_STR_ROLE");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, MINTER_STR_ROLE)
        );
        strTokenReceipt.mint(bob, 100 ether);
        vm.stopPrank();
    }

    function testMint() external {
        vm.startPrank(owner);
        strTokenReceipt.mint(owner, 100 ether);
        vm.stopPrank();

        uint256 balance = ERC20(strTokenReceipt).balanceOf(owner);
        assertEq(balance, 100 ether);
    }

    modifier hasMinted() {
        vm.startPrank(owner);
        strTokenReceipt.mint(owner, 100 ether);
        vm.stopPrank();
        _;
    }

    function testReverBurn() external hasMinted {
        vm.startPrank(bob);
        bytes32 BURNER_STR_ROLE = keccak256("BURNER_STR_ROLE");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, BURNER_STR_ROLE)
        );
        strTokenReceipt.burn(bob, 100 ether);
        vm.stopPrank();
    }

    function testBurn() external hasMinted {
        uint256 balance = ERC20(strTokenReceipt).balanceOf(owner);
        assertEq(balance, 100 ether);

        vm.startPrank(owner);
        strTokenReceipt.burn(owner, 100 ether);
        vm.stopPrank();

        uint256 endBalance = ERC20(strTokenReceipt).balanceOf(owner);
        assertEq(endBalance, 0);
    }
}
