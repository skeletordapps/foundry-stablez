// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ISTRTokenReceipt {
    function mint(address recipient, uint256 amount) external;
    function burn(address recipient, uint256 amount) external;
}
