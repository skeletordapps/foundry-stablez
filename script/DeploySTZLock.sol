// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {STZToken} from "../src/STZToken.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";
import {STZLock} from "../src/STZLock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploySTZToken} from "../script/DeploySTZToken.s.sol";
import {DeploySTRTokenReceipt} from "../script/DeploySTRTokenReceipt.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeploySTZLock is Script {
    function run() external returns (STZToken stz, STRTokenReceipt str, IERC20 weth, STZLock stzLock) {
        vm.startBroadcast();
        stz = new STZToken();
        str = new STRTokenReceipt();

        if (block.chainid != 31337) {
            weth = IERC20(vm.envAddress("WETH"));
        } else {
            ERC20Mock mock = new ERC20Mock();
            weth = IERC20(address(mock));
        }

        stzLock = new STZLock(address(stz), address(str), address(weth));
        vm.stopBroadcast();

        return (stz, str, weth, stzLock);
    }

    function testMock() public {}
}
