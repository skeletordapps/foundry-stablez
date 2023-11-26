// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

interface ISTRTokenReceipt {
    function mint(address recipient, uint256 amount) external;
    function burn(address recipient, uint256 amount) external;
}
