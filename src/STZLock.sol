// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISTZToken} from "../src/interfaces/ISTZToken.sol";
import {ISTRTokenReceipt} from "../src/interfaces/ISTRTokenReceipt.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console2} from "forge-std/console2.sol";

contract STZLock is Ownable {
    using SafeERC20 for IERC20;

    ISTZToken public immutable stzToken;
    ISTRTokenReceipt public immutable strTokenReceipt;

    mapping(address account => uint256 amount) public locks;

    constructor(address stzAddress, address strAddress) Ownable(msg.sender) {
        stzToken = ISTZToken(stzAddress);
        strTokenReceipt = ISTRTokenReceipt(strAddress);
    }

    function lock(uint256 amount) external {
        IERC20(address(stzToken)).safeTransferFrom(msg.sender, address(this), amount);
        locks[msg.sender] += amount;

        strTokenReceipt.mint(address(this), amount);
        stzToken.burn(address(this), amount);

        IERC20(address(strTokenReceipt)).safeTransfer(msg.sender, amount);
    }

    function unlock(uint256 amount) external {
        IERC20(address(strTokenReceipt)).safeTransferFrom(msg.sender, address(this), amount);
        locks[msg.sender] -= amount;

        stzToken.mint(address(this), amount);
        strTokenReceipt.burn(address(this), amount);

        IERC20(address(stzToken)).safeTransfer(msg.sender, amount);
    }
}
