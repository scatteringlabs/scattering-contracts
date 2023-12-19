// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Errors {
    /// @notice Safe Box error
    error SafeBoxHasExpire();
    error SafeBoxNotExist();
    error SafeBoxHasNotExpire();
    error SafeBoxAlreadyExist();
    error NoMatchingSafeBoxKey();
    error SafeBoxKeyAlreadyExist();

    /// @notice Auction error
    error AuctionHasNotCompleted();
    error AuctionHasExpire();
    error AuctionBidIsNotHighEnough();
    error AuctionBidTokenMismatch();
    error AuctionSelfBid();
    error AuctionInvalidBidAmount();
    error AuctionNotExist();
    error SafeBoxAuctionWindowHasPassed();

    /// @notice Activity common error
    error NftHasActiveActivities();
    error ActivityHasNotCompleted();
    error ActivityHasExpired();
    error ActivityNotExist();

    /// @notice User account error
    error InsufficientFund();
    error InsufficientCredit();
    error NoPrivilege();

    /// @notice Parameter error
    error InvalidParam();
    error NftCollectionNotSupported();
    error NftCollectionAlreadySupported();
    error ClaimableNftInsufficient();
    error TokenNotSupported();
    error AmountTooSmall(uint256 minAmount, uint256 throwAmount);

    error DisabledFunction();
}
