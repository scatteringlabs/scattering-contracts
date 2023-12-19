// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

contract TestERC20 is ERC20, AccessControlEnumerable {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 s_decimals) ERC20(name, symbol) {
        _decimals = s_decimals;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
