// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../Errors.sol";
import "../interface/IScattering.sol";
import {SafeBox, CollectionState, PrivateOffer} from "./Structs.sol";
import {SafeBoxLib} from "./SafeBox.sol";
import "./User.sol";
import "./Helper.sol";
import "./Collection.sol";

library PrivateOfferLib {
    using SafeBoxLib for SafeBox;
    using UserLib for UserFloorAccount;
    using Helper for CollectionState;
    using CollectionLib for CollectionState;

    // todo: event should be moved to Interface as far as Solidity 0.8.22 ready.
    // https://github.com/ethereum/solidity/pull/14274
    // https://github.com/ethereum/solidity/issues/14430
    event PrivateOfferStarted(
        address indexed seller,
        address indexed buyer,
        address indexed collection,
        uint64[] activityIds,
        uint256[] nftIds,
        address settleToken,
        uint96 price,
        //        uint256 offerEndTime,
        //        uint256 safeBoxExpiryTs,
        uint256 adminFee
    );

    event PrivateOfferCanceled(
        address indexed operator,
        address indexed collection,
        uint64[] activityIds,
        uint256[] nftIds
    );

    event PrivateOfferAccepted(
        address indexed buyer,
        address indexed collection,
        uint64[] activityIds,
        uint256[] nftIds,
        uint256[] safeBoxKeyIds
    );

    struct PrivateOfferSettlement {
        uint256 keyId;
        uint256 nftId;
        address token;
        uint128 collectedFund;
        address seller;
        address buyer;
    }

    function ownerInitPrivateOffers(
        CollectionState storage collection,
        // mapping(address => UserFloorAccount) storage userAccounts,
        // address creditToken,
        IScattering.PrivateOfferInitParam memory param
    ) public {
        // creditToken;
        if (param.receiver == msg.sender) revert Errors.InvalidParam();
        /// if receiver is none, means list and anyone can buy it
        if (param.receiver == address(0)) {
            return startListOffer(collection, /*userAccounts,*/ param);
        }

        PrivateOffer memory offerTemplate = PrivateOffer({
            activityId: 0,
            token: param.token,
            price: param.price,
            owner: msg.sender,
            buyer: param.receiver
        });

        uint64[] memory offerActivityIds = _ownerInitPrivateOffers(
            collection,
            //            userAccount.getByKey(param.collection),
            param.nftIds,
            offerTemplate
        );

        emit PrivateOfferStarted(
            msg.sender,
            param.receiver,
            param.collection,
            offerActivityIds,
            param.nftIds,
            param.token,
            param.price,
            0
        );
    }

    function _ownerInitPrivateOffers(
        CollectionState storage collection,
        uint256[] memory nftIds,
        PrivateOffer memory offerTemplate
    ) private returns (uint64[] memory offerActivityIds) {
        uint256 nftLen = nftIds.length;
        offerActivityIds = new uint64[](nftLen);

        for (uint256 i; i < nftLen; ) {
            uint256 nftId = nftIds[i];
            if (collection.hasActiveActivities(nftId)) revert Errors.NftHasActiveActivities();

            /// dummy check
            collection.useSafeBoxAndKey(msg.sender, nftId);

            offerTemplate.activityId = collection.generateNextActivityId();
            collection.activePrivateOffers[nftId] = offerTemplate;
            offerActivityIds[i] = offerTemplate.activityId;

            unchecked {
                ++i;
            }
        }
    }

    function startListOffer(
        CollectionState storage collection,
        //        mapping(address => UserFloorAccount) storage userAccounts,
        IScattering.PrivateOfferInitParam memory param
    ) internal {
        //        if (feeConf.safeboxFee.receipt == address(0)) revert Errors.TokenNotSupported();

        PrivateOffer memory template = PrivateOffer({
            activityId: 0,
            token: param.token,
            price: param.price,
            owner: msg.sender,
            buyer: address(0)
        });
        //        CollectionAccount storage ownerCollection = userAccounts[msg.sender].getByKey(param.collection);

        uint64[] memory activityIds = new uint64[](param.nftIds.length);
        for (uint256 i; i < param.nftIds.length; ) {
            uint256 nftId = param.nftIds[i];
            if (collection.hasActiveActivities(nftId)) revert Errors.NftHasActiveActivities();

            /// check owner and safe box time valid and key id exist
            collection.useSafeBoxAndKey(msg.sender, nftId);

            template.activityId = Helper.generateNextActivityId(collection);
            collection.activePrivateOffers[nftId] = template;

            activityIds[i] = template.activityId;
            unchecked {
                ++i;
            }
        }

        emit PrivateOfferStarted(
            msg.sender,
            address(0), // buyer no restrictions
            param.collection,
            activityIds,
            param.nftIds,
            param.token,
            param.price,
            0
        );
    }

    function removePrivateOffers(
        CollectionState storage collection,
        address collectionId,
        uint256[] memory nftIds
    ) public {
        uint64[] memory offerActivityIds = new uint64[](nftIds.length);
        for (uint256 i; i < nftIds.length; ) {
            uint256 nftId = nftIds[i];
            PrivateOffer storage offer = collection.activePrivateOffers[nftId];
            if (offer.owner != msg.sender && offer.buyer != msg.sender) revert Errors.NoPrivilege();

            offerActivityIds[i] = offer.activityId;
            delete collection.activePrivateOffers[nftId];

            unchecked {
                ++i;
            }
        }

        emit PrivateOfferCanceled(msg.sender, collectionId, offerActivityIds, nftIds);
    }

    function buyerAcceptPrivateOffers(
        CollectionState storage collection,
        mapping(address => UserFloorAccount) storage userAccounts,
        address collectionId,
        uint256[] memory nftIds /*,
        address creditToken*/
    ) public {
        (PrivateOfferSettlement[] memory settlements, uint64[] memory activityIds) = _buyerAcceptPrivateOffers(
            collection,
            nftIds
        );

        uint256 totalCost;
        uint256[] memory safeBoxKeyIds = new uint256[](settlements.length);
        uint256 settlementLen = settlements.length;
        for (uint256 i; i < settlementLen; ) {
            PrivateOfferSettlement memory settlement = settlements[i];

            if (settlement.collectedFund > 0) {
                totalCost += settlement.collectedFund;
            }

            safeBoxKeyIds[i] = settlement.keyId;

            unchecked {
                ++i;
            }
        }

        if (totalCost > 0 && settlementLen > 0) {
            // @notice todo The 'settlement.token' must ensure that all settlement tokens are the same when the user creates them, so it cannot be too personalized.
            PrivateOfferSettlement memory settlement = settlements[0];
            UserFloorAccount storage buyerAccount = userAccounts[settlement.buyer];
            UserFloorAccount storage sellerAccount = userAccounts[settlement.seller];
            address settleToken = settlement.token;
            uint256 protocolFee = (totalCost * Constants.OFFER_FEE_RATE_BIPS) / 10_000;
            uint256 priceWithoutFee;
            unchecked {
                priceWithoutFee = totalCost - protocolFee;
            }
            // @notice todo Future support for royalty NFTs, paying attention to the receiving token and taxes.
            buyerAccount.transferToken(userAccounts[address(this)], settleToken, protocolFee, false);
            {
                buyerAccount.transferToken(sellerAccount, settleToken, priceWithoutFee, false);
                sellerAccount.withdraw(settlement.seller, settleToken, priceWithoutFee, false);
            }
        }
        emit PrivateOfferAccepted(msg.sender, collectionId, activityIds, nftIds, safeBoxKeyIds);
    }

    function _buyerAcceptPrivateOffers(
        CollectionState storage collection,
        uint256[] memory nftIds
    ) private returns (PrivateOfferSettlement[] memory settlements, uint64[] memory offerActivityIds) {
        uint256 nftLen = nftIds.length;
        settlements = new PrivateOfferSettlement[](nftLen);
        offerActivityIds = new uint64[](nftLen);
        for (uint256 i; i < nftLen; ) {
            uint256 nftId = nftIds[i];
            // todo Use 'buyer' to distinguish between public and private offer.
            if (!Helper.hasActiveListOffer(collection, nftId) && !Helper.hasActivePrivateOffer(collection, nftId)) {
                revert Errors.ActivityNotExist();
            }
            PrivateOffer storage offer = collection.activePrivateOffers[nftId];
            //if (offer.endTime <= block.timestamp) revert Errors.ActivityHasExpired();
            // todo when buyer!=zero addr, buyer must == msg.sender
            if (offer.buyer != address(0) && offer.buyer != msg.sender) revert Errors.NoPrivilege();
            if (offer.owner == msg.sender) revert Errors.NoPrivilege();

            SafeBox storage safeBox = collection.useSafeBox(nftId);
            /// this revert couldn't happen but just leaving it (we have checked offer'EndTime before)
            if (safeBox.isSafeBoxExpired()) revert Errors.SafeBoxHasExpire();

            collection.transferSafeBox(safeBox, msg.sender);

            settlements[i] = PrivateOfferSettlement({
                keyId: safeBox.keyId,
                nftId: nftId,
                seller: offer.owner,
                buyer: msg.sender,
                token: offer.token,
                collectedFund: offer.price
            });
            offerActivityIds[i] = offer.activityId;

            delete collection.activePrivateOffers[nftId];

            unchecked {
                ++i;
            }
        }
    }
}
