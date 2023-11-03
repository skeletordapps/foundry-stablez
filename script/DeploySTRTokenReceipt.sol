// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {STRTokenReceipt} from "../src/STRTokenReceipt.sol";

contract DeploySTRTokenReceipt is Script {
    function run() external returns (STRTokenReceipt strTokenReceipt) {
        // uint256 deployerKey = vm.envUint("DEFAULT_ANVIL_KEY");

        // vm.startBroadcast(deployerKey);
        vm.startBroadcast();
        strTokenReceipt = new STRTokenReceipt();
        vm.stopBroadcast();

        return (strTokenReceipt);
    }

    function testMock() public {}
}
