// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract STZToken is ERC20, Ownable {
    constructor() ERC20("StableZ", "STZ") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000 ether);
    }
}
