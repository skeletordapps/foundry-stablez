// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract STRTokenReceipt is ERC20, Ownable, AccessControl {
    bytes32 public constant MINTER_STR_ROLE = keccak256("MINTER_STR_ROLE");
    bytes32 public constant BURNER_STR_ROLE = keccak256("BURNER_STR_ROLE");

    constructor() ERC20("StableZ Receipt", "STR") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_STR_ROLE, msg.sender);
        _grantRole(BURNER_STR_ROLE, msg.sender);
    }

    // EXTERNAL FUNCTIONS

    function mint(address recipient, uint256 amount) external onlyRole(MINTER_STR_ROLE) {
        _mint(recipient, amount);
    }

    function burn(address recipient, uint256 amount) external onlyRole(BURNER_STR_ROLE) {
        _burn(recipient, amount);
    }

    // PUBLIC FUNCTIONS

    function grantMintRole(address account) public onlyOwner {
        grantRole(MINTER_STR_ROLE, account);
    }

    function grantBurnRole(address account) public onlyOwner {
        _grantRole(BURNER_STR_ROLE, account);
    }

    function revokeMintRole(address account) public onlyOwner {
        _grantRole(MINTER_STR_ROLE, account);
    }

    function revokeBurnRole(address account) public onlyOwner {
        _grantRole(BURNER_STR_ROLE, account);
    }
}
