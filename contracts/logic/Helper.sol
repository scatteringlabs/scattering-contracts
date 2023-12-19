// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../Constants.sol";
import "../Errors.sol";
import "./SafeBox.sol";
import "./User.sol";
import {SafeBox, CollectionState, AuctionInfo, PrivateOffer} from "./Structs.sol";

library Helper {
    using SafeBoxLib for SafeBox;

    // @notice Check if the safeBox is still within the validity period and verify if the owner is consistent
    function useSafeBoxAndKey(
        CollectionState storage collection,
        address userAccount,
        uint256 nftId
    ) internal view returns (SafeBox storage safeBox /*, SafeBoxKey storage key*/) {
        safeBox = collection.safeBoxes[nftId];
        if (safeBox.keyId == 0) revert Errors.SafeBoxNotExist();
        if (safeBox.isSafeBoxExpired()) revert Errors.SafeBoxHasExpire();
        if (safeBox.owner != userAccount) {
            revert Errors.NoMatchingSafeBoxKey();
        }
        //        key = userAccount.getByKey(nftId);
        //        if (!safeBox.isKeyMatchingSafeBox(key)) revert Errors.NoMatchingSafeBoxKey();
    }

    function useSafeBox(
        CollectionState storage collection,
        uint256 nftId
    ) internal view returns (SafeBox storage safeBox) {
        safeBox = collection.safeBoxes[nftId];
        if (safeBox.keyId == 0) revert Errors.SafeBoxNotExist();
    }

    function generateNextKeyId(CollectionState storage collectionState) internal returns (uint64 nextKeyId) {
        nextKeyId = collectionState.nextKeyId;
        ++collectionState.nextKeyId;
    }

    function generateNextActivityId(CollectionState storage collection) internal returns (uint64 nextActivityId) {
        nextActivityId = collection.nextActivityId;
        ++collection.nextActivityId;
    }

    function isAuctionPeriodOver(SafeBox storage safeBox) internal view returns (bool) {
        return safeBox.expiryTs + Constants.FREE_AUCTION_PERIOD < block.timestamp;
    }

    function hasActiveActivities(CollectionState storage collection, uint256 nftId) internal view returns (bool) {
        return
            hasActiveAuction(collection, nftId) ||
            hasActiveRaffle(collection, nftId) ||
            hasActivePrivateOffer(collection, nftId) ||
            hasActiveListOffer(collection, nftId);
    }

    function hasActiveAuction(CollectionState storage collection, uint256 nftId) internal view returns (bool) {
        return collection.activeAuctions[nftId].endTime >= block.timestamp;
    }

    function hasActiveRaffle(CollectionState storage collection, uint256 nftId) internal view returns (bool) {
        // todo For the raffle, an end time needs to be set
        return collection.activeRaffles[nftId].endTime >= block.timestamp;
    }

    function hasActivePrivateOffer(CollectionState storage collection, uint256 nftId) internal view returns (bool) {
        // todo Do not need to set an end time for the order, first check the validity period of the SafeBox, and then verify if it is active
        // return collection.activePrivateOffers[nftId].endTime >= block.timestamp;
        return
            collection.safeBoxes[nftId].expiryTs >= block.timestamp &&
            collection.activePrivateOffers[nftId].owner != address(0);
    }

    function hasActiveListOffer(CollectionState storage collection, uint256 nftId) internal view returns (bool) {
        PrivateOffer storage offer = collection.activePrivateOffers[nftId];
        return offer.activityId > 0 && offer.buyer == address(0) && !useSafeBox(collection, nftId).isSafeBoxExpired();
    }

    //    function getTokenFeeRateBips(
    //        address creditToken,
    //        address fragmentToken,
    //        address settleToken
    //    ) internal pure returns (uint256) {
    //        uint256 feeRateBips = Constants.COMMON_FEE_RATE_BIPS;
    //        if (settleToken == creditToken) {
    //            feeRateBips = Constants.CREDIT_FEE_RATE_BIPS;
    //        } else if (settleToken == fragmentToken) {
    //            feeRateBips = Constants.SPEC_FEE_RATE_BIPS;
    //        }
    //
    //        return feeRateBips;
    //    }

    function getTokenFeeRateBips() internal pure returns (uint256) {
        return Constants.COMMON_FEE_RATE_BIPS;
    }

    function calculateActivityFee(
        uint256 settleAmount,
        uint256 feeRateBips
    ) internal pure returns (uint256 afterFee, uint256 fee) {
        fee = (settleAmount * feeRateBips) / 10000;
        unchecked {
            afterFee = settleAmount - fee;
        }
    }

    function calculateLockingRatio(
        CollectionState storage collection,
        uint256 newLocked
    ) internal view returns (uint256) {
        uint256 freeAmount = collection.freeTokenIds.length;
        uint256 totalManaged = newLocked + collection.activeSafeBoxCnt + freeAmount;
        return calculateLockingRatioRaw(freeAmount, totalManaged);
    }

    function calculateLockingRatioRaw(uint256 freeAmount, uint256 totalManaged) internal pure returns (uint256) {
        if (totalManaged == 0) {
            return 0;
        } else {
            unchecked {
                return (100 - (freeAmount * 100) / totalManaged);
            }
        }
    }
}
