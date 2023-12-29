// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SafeBox, CollectionState, RaffleInfo, TicketRecord} from "./Structs.sol";
import "./User.sol";
import "./Collection.sol";
import "./Helper.sol";
import "../Errors.sol";
import "../library/Array.sol";

library RaffleLib {
    using CollectionLib for CollectionState;
    using SafeBoxLib for SafeBox;
    using UserLib for UserFloorAccount;
    using Helper for CollectionState;

    event RaffleStarted(
        address indexed owner,
        address indexed collection,
        uint64[] activityIds,
        uint256[] nftIds,
        uint48 maxTickets,
        address settleToken,
        uint96 ticketPrice,
        uint256 feeRateBips,
        uint48 raffleEndTime,
        uint256 safeBoxExpiryTs,
        uint256 adminFee
    );

    event RaffleTicketsSold(
        address indexed buyer,
        address indexed collection,
        uint64 activityId,
        uint256 nftId,
        uint256 ticketsSold,
        uint256 cost
    );

    event RaffleSettled(
        address indexed winner,
        address indexed collection,
        uint64 activityId,
        uint256 nftId,
        uint256 safeBoxKeyId,
        uint256 collectedFunds
    );

    function ownerInitRaffles(
        CollectionState storage collection,
        mapping(address => UserFloorAccount) storage userAccounts,
        IScattering.RaffleInitParam memory param /*,
        address creditToken*/
    ) public {
        UserFloorAccount storage userAccount = userAccounts[msg.sender];

        {
            if (uint256(param.maxTickets) * param.ticketPrice > type(uint96).max) revert Errors.InvalidParam();

            // todo Duration of the raffle activity
            param.duration = Constants.raffleDurations();
        }

        uint256 adminFee = Constants.RAFFLE_COST * param.nftIds.length;
        userAccount.transferToken(userAccounts[address(this)], address(collection.fragmentToken), adminFee, true);

        uint256 feeRateBips = Helper.getTokenFeeRateBips();
        (uint64[] memory raffleActivityIds, uint48 raffleEndTime, uint192 safeBoxExpiryTs) = _ownerInitRaffles(
            collection,
            param,
            uint32(feeRateBips)
        );

        emit RaffleStarted(
            msg.sender,
            param.collection,
            raffleActivityIds,
            param.nftIds,
            param.maxTickets,
            param.ticketToken,
            param.ticketPrice,
            feeRateBips,
            raffleEndTime,
            safeBoxExpiryTs,
            adminFee
        );
    }

    function _ownerInitRaffles(
        CollectionState storage collection,
        IScattering.RaffleInitParam memory param,
        uint32 feeRateBips
    ) private returns (uint64[] memory raffleActivityIds, uint48 raffleEndTime, uint32 safeBoxExpiryTs) {
        raffleEndTime = uint48(block.timestamp + param.duration);
        safeBoxExpiryTs = uint32(raffleEndTime + Constants.RAFFLE_COMPLETE_GRACE_PERIODS);

        raffleActivityIds = new uint64[](param.nftIds.length);
        for (uint256 i; i < param.nftIds.length; ) {
            uint256 nftId = param.nftIds[i];

            if (collection.hasActiveActivities(nftId)) revert Errors.NftHasActiveActivities();

            SafeBox storage safeBox = collection.useSafeBoxAndKey(msg.sender, nftId);

            safeBox.expiryTs = safeBoxExpiryTs;
            raffleActivityIds[i] = collection.generateNextActivityId();

            RaffleInfo storage newRaffle = collection.activeRaffles[nftId];
            newRaffle.endTime = raffleEndTime;
            newRaffle.token = param.ticketToken;
            newRaffle.ticketPrice = param.ticketPrice;
            newRaffle.maxTickets = param.maxTickets;
            newRaffle.owner = msg.sender;
            newRaffle.activityId = raffleActivityIds[i];
            newRaffle.feeRateBips = feeRateBips;

            unchecked {
                ++i;
            }
        }
    }

    function buyRaffleTickets(
        CollectionState storage collection,
        mapping(address => UserFloorAccount) storage accounts,
        // address creditToken,
        address collectionId,
        uint256 nftId,
        uint256 ticketCnt
    ) public {
        RaffleInfo storage raffle = collection.activeRaffles[nftId];
        if (raffle.owner == address(0) || raffle.owner == msg.sender) revert Errors.NoPrivilege();
        if (raffle.endTime < block.timestamp) revert Errors.ActivityHasExpired();
        if (raffle.maxTickets < raffle.ticketSold + ticketCnt) revert Errors.InvalidParam();

        //        SafeBox storage safeBox = collection.useSafeBox(nftId);
        //        safeBox.keyId = SafeBoxLib.SAFEBOX_KEY_NOTATION;

        // buyer buy tickets idx in [startIdx, endIdx)
        raffle.tickets.push(
            TicketRecord({
                buyer: msg.sender,
                startIdx: uint48(raffle.ticketSold),
                endIdx: uint48(raffle.ticketSold + ticketCnt)
            })
        );

        uint256 cost = raffle.ticketPrice * ticketCnt;
        raffle.ticketSold += uint48(ticketCnt);
        raffle.collectedFund += uint96(cost);

        address token = raffle.token;
        accounts[msg.sender].transferToken(accounts[address(this)], token, cost, /* token == creditToken*/ false);

        emit RaffleTicketsSold(msg.sender, collectionId, raffle.activityId, nftId, ticketCnt, cost);
    }

    function prepareSettleRaffles(
        CollectionState storage collection,
        uint256[] calldata nftIds
    ) public returns (bytes memory compactedNftIds, uint256 nftLen) {
        nftLen = nftIds.length;
        uint256[] memory tmpNftIds = new uint256[](nftLen);
        uint256 cnt;
        for (uint256 i; i < nftLen; ++i) {
            uint256 nftId = nftIds[i];
            RaffleInfo storage raffle = collection.activeRaffles[nftId];

            if (raffle.endTime >= block.timestamp) revert Errors.ActivityHasNotCompleted();
            if (raffle.isSettling) revert Errors.InvalidParam();

            if (raffle.ticketSold == 0) {
                continue;
            }

            SafeBox storage safeBox = collection.useSafeBox(nftId);
            // raffle must be settled before safebox expired
            // otherwise it maybe conflict with auction
            if (safeBox.isSafeBoxExpired()) revert Errors.SafeBoxHasExpire();

            tmpNftIds[cnt] = nftId;
            raffle.isSettling = true;

            unchecked {
                ++cnt;
            }
        }

        /// only allow up to 8 raffles can be settled
        if (cnt > 8) revert Errors.InvalidParam();

        if (cnt == nftLen) {
            // the first line of the code has already made the same assignment
            // nftIdsLen = tmpNftIds.length;
            compactedNftIds = Array.encodeUints(tmpNftIds);
        } else {
            nftLen = cnt;
            compactedNftIds = Array.encodeUints(Array.slice(tmpNftIds, 0, cnt));
        }
    }

    function settleRaffles(
        CollectionState storage collection,
        mapping(address => UserFloorAccount) storage userAccounts,
        address collectionId,
        bytes memory compactedNftIds,
        uint256[] memory randoms
    ) public {
        uint256[] memory nftIds = Array.decodeUints(compactedNftIds);
        for (uint256 i; i < nftIds.length; ) {
            uint256 nftId = nftIds[i];
            RaffleInfo storage raffle = collection.activeRaffles[nftId];

            TicketRecord memory winTicket = getWinTicket(raffle.tickets, uint48(randoms[i] % raffle.ticketSold));

            /// we don't check whether the safebox is exist, it had done in the `prepareSettleRaffles`
            SafeBox storage safeBox = collection.safeBoxes[nftId];
            collection.transferSafeBox(safeBox, winTicket.buyer);

            (uint256 earning, ) = Helper.calculateActivityFee(raffle.collectedFund, raffle.feeRateBips);
            /// contract account no need to check credit requirements
            userAccounts[address(this)].transferToken(userAccounts[raffle.owner], raffle.token, earning, false);
            userAccounts[raffle.owner].withdraw(raffle.owner, raffle.token, earning, false);

            emit RaffleSettled(
                winTicket.buyer,
                collectionId,
                raffle.activityId,
                nftId,
                safeBox.keyId,
                raffle.collectedFund
            );

            delete collection.activeRaffles[nftId];

            unchecked {
                ++i;
            }
        }
    }

    function getWinTicket(
        TicketRecord[] storage tickets,
        uint48 idx
    ) private view returns (TicketRecord memory ticket) {
        uint256 low;
        uint256 high = tickets.length;

        unchecked {
            while (low <= high) {
                // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
                // because Math.average rounds down (it does integer division with truncation).
                uint256 mid = Math.average(low, high);

                ticket = tickets[mid];
                if (ticket.startIdx <= idx && idx < ticket.endIdx) {
                    return ticket;
                }

                if (ticket.startIdx < idx) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }
}
