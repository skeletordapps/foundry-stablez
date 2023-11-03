// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {STZToken} from "../src/STZToken.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";
import {STZLock} from "../src/STZLock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DeploySTZToken} from "../script/DeploySTZToken.s.sol";
import {DeploySTRTokenReceipt} from "../script/DeploySTRTokenReceipt.sol";

contract DeploySTZLock is Script {
    function run() external returns (STZToken stzToken, STRTokenReceipt strTokenReceipt, STZLock stzLock) {
        vm.startBroadcast();
        stzToken = new STZToken();
        strTokenReceipt = new STRTokenReceipt();
        stzLock = new STZLock(address(stzToken), address(strTokenReceipt));
        vm.stopBroadcast();

        return (stzToken, strTokenReceipt, stzLock);
    }

    function testMock() public {}
}
