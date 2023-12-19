// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "./../interface/IFragmentToken.sol";

contract TestFragmentToken is ERC20, IFragmentToken, Ownable2Step {
    address public trustedCallerAddress;

    constructor(string memory name, string memory symbol, address _owner) ERC20(name, symbol) Ownable(_owner) {}

    modifier onlyTrustedCaller() {
        if (msg.sender != trustedCallerAddress) revert CallerIsNotTrustedContract();
        _;
    }

    function setTrustedCaller(address _trustedCaller) external onlyOwner {
        trustedCallerAddress = _trustedCaller;
    }

    function mint(address account, uint256 amount) public onlyTrustedCaller {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyTrustedCaller {
        _burn(account, amount);
    }
}
