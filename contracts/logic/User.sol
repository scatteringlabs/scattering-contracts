// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import "../Constants.sol";
import "../Errors.sol";
import "../library/CurrencyTransfer.sol";
import {UserFloorAccount} from "./Structs.sol";

library UserLib {
    using SafeCast for uint256;

    /// @notice `sender` deposit `token` into Scattering on behalf of `receiver`. `receiver`'s account will be updated.
    event DepositToken(address indexed sender, address indexed receiver, address indexed token, uint256 amount);
    /// @notice `sender` withdraw `token` from Scattering and transfer it to `receiver`.
    event WithdrawToken(address indexed sender, address indexed receiver, address indexed token, uint256 amount);

    address internal constant LIST_GUARD = address(1);

    function deposit(
        UserFloorAccount storage account,
        address onBehalfOf,
        address token,
        uint256 amount,
        bool isLockCredit
    ) public {
        depositToken(account, token, amount);
        isLockCredit;

        if (token == CurrencyTransfer.NATIVE) {
            if (amount != msg.value) {
                revert Errors.InsufficientFund();
            }
        } else {
            CurrencyTransfer.safeTransferFrom(token, msg.sender, address(this), amount);
        }
        emit DepositToken(msg.sender, onBehalfOf, token, amount);
    }

    function withdraw(
        UserFloorAccount storage account,
        address receiver,
        address token,
        uint256 amount,
        bool isCredit
    ) public {
        withdrawToken(account, token, amount, isCredit);
        CurrencyTransfer.safeTransfer(token, receiver, amount);
        emit WithdrawToken(msg.sender, receiver, token, amount);
    }

    function tokenBalance(UserFloorAccount storage account, address token) internal view returns (uint256) {
        return account.tokenAmounts[token];
    }

    function depositToken(UserFloorAccount storage account, address token, uint256 amount) internal {
        account.tokenAmounts[token] += amount;
    }

    function withdrawToken(
        UserFloorAccount storage account,
        address token,
        uint256 amount,
        bool isCreditToken
    ) internal {
        uint256 balance = account.tokenAmounts[token];
        if (balance < amount) {
            revert Errors.InsufficientCredit();
        }

        // todo nothing to do
        if (isCreditToken) {
            uint256 availableBuf;
            unchecked {
                availableBuf = balance - amount;
            }

            account.tokenAmounts[token] = availableBuf;
        } else {
            unchecked {
                account.tokenAmounts[token] = balance - amount;
            }
        }
    }

    function transferToken(
        UserFloorAccount storage from,
        UserFloorAccount storage to,
        address token,
        uint256 amount,
        bool isCreditToken
    ) internal {
        withdrawToken(from, token, amount, isCreditToken);
        depositToken(to, token, amount);
    }
}
