// // SPDX-License-Identifier: UNLINCENSED
// pragma solidity ^0.8.23;

// import {Test} from "forge-std/Test.sol";
// import {DeploySTZToken} from "../script/DeploySTZToken.s.sol";
// import {STZToken} from "../src/STZToken.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// contract STZTokenTest is Test {
//     DeploySTZToken deployer;
//     STZToken stzToken;
//     address owner;
//     address bob;

//     function setUp() public virtual {
//         deployer = new DeploySTZToken();
//         stzToken = deployer.run();
//         owner = stzToken.owner();
//         bob = vm.addr(1);
//         vm.label(bob, "bob");
//     }

//     function testRevertMint() external {
//         vm.startPrank(bob);
//         bytes32 MINTER_STZ_ROLE = keccak256("MINTER_STZ_ROLE");
//         vm.expectRevert(
//             abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, MINTER_STZ_ROLE)
//         );
//         stzToken.mint(bob, 100 ether);
//         vm.stopPrank();
//     }

//     function testMint() external {
//         vm.startPrank(owner);
//         stzToken.mint(owner, 100 ether);
//         vm.stopPrank();

//         uint256 balance = ERC20(stzToken).balanceOf(owner);
//         assertEq(balance, 100 ether);
//     }

//     modifier hasMinted() {
//         vm.startPrank(owner);
//         stzToken.mint(owner, 100 ether);
//         vm.stopPrank();
//         _;
//     }

//     function testReverBurn() external hasMinted {
//         vm.startPrank(bob);
//         bytes32 BURNER_STZ_ROLE = keccak256("BURNER_STZ_ROLE");
//         vm.expectRevert(
//             abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, BURNER_STZ_ROLE)
//         );
//         stzToken.burn(bob, 100 ether);
//         vm.stopPrank();
//     }

//     function testBurn() external hasMinted {
//         uint256 balance = ERC20(stzToken).balanceOf(owner);
//         assertEq(balance, 100 ether);

//         vm.startPrank(owner);
//         stzToken.burn(owner, 100 ether);
//         vm.stopPrank();

//         uint256 endBalance = ERC20(stzToken).balanceOf(owner);
//         assertEq(endBalance, 0);
//     }
// }
