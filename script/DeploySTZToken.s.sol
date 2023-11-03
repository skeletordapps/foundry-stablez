// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {STZToken} from "../src/STZToken.sol";

contract DeploySTZToken is Script {
    function run() external returns (STZToken stzToken) {
        // uint256 deployerKey = vm.envUint("DEFAULT_ANVIL_KEY");

        // vm.startBroadcast(deployerKey);
        vm.startBroadcast();
        stzToken = new STZToken();
        vm.stopBroadcast();

        return (stzToken);
    }

    function testMock() public {}
}
