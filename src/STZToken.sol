// SPDX-License-Identifier: UNLINCENSED
pragma solidity ^0.8.22;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract STZToken is ERC20, Ownable, AccessControl {
    bytes32 public constant MINTER_STZ_ROLE = keccak256("MINTER_STZ_ROLE");
    bytes32 public constant BURNER_STZ_ROLE = keccak256("BURNER_STZ_ROLE");

    constructor() ERC20("StableZ", "STZ") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_STZ_ROLE, msg.sender);
        _grantRole(BURNER_STZ_ROLE, msg.sender);
    }

    // EXTERNAL FUNCTIONS

    function mint(address recipient, uint256 amount) external onlyRole(MINTER_STZ_ROLE) {
        _mint(recipient, amount);
    }

    function burn(address recipient, uint256 amount) external onlyRole(BURNER_STZ_ROLE) {
        _burn(recipient, amount);
    }

    // PUBLIC FUNCTIONS

    function grantMintRole(address account) public onlyOwner {
        grantRole(MINTER_STZ_ROLE, account);
    }

    function grantBurnRole(address account) public onlyOwner {
        _grantRole(BURNER_STZ_ROLE, account);
    }

    function revokeMintRole(address account) public onlyOwner {
        _grantRole(MINTER_STZ_ROLE, account);
    }

    function revokeBurnRole(address account) public onlyOwner {
        _grantRole(BURNER_STZ_ROLE, account);
    }
}
