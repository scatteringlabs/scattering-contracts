// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interface/IScattering.sol";
import "./Constants.sol";
import {TicketRecord, SafeBox, AuctionType} from "./logic/Structs.sol";

contract ScatteringGetter {
    IScattering public _scattering;

    uint256 internal constant COLLECTION_STATES_SLOT = 1;
    uint256 internal constant USER_ACCOUNTS_SLOT = 2;
    uint256 internal constant SUPPORTED_TOKENS_SLOT = 3;
    uint256 internal constant COLLECTION_PROXY_SLOT = 4;
    uint256 internal constant TRIAL_DAYS_SLOT = 5;
    uint256 internal constant PAYMENT_AMOUNT_SLOT = 6;

    uint256 internal constant MASK_32 = (1 << 32) - 1;
    uint256 internal constant MASK_48 = (1 << 48) - 1;
    uint256 internal constant MASK_64 = (1 << 64) - 1;
    uint256 internal constant MASK_96 = (1 << 96) - 1;
    uint256 internal constant MASK_128 = (1 << 128) - 1;
    uint256 internal constant MASK_160 = (1 << 160) - 1;

    function supportedToken(address token) public view returns (bool) {
        uint256 val = uint256(_scattering.extsload(keccak256(abi.encode(token, SUPPORTED_TOKENS_SLOT))));

        return val != 0;
    }

    function collectionProxy(address proxy) public view returns (address) {
        address underlying = address(
            uint160(uint256(_scattering.extsload(keccak256(abi.encode(proxy, COLLECTION_PROXY_SLOT)))))
        );
        return underlying;
    }

    function fragmentTokenOf(address collection) public view returns (address token) {
        bytes32 val = _scattering.extsload(keccak256(abi.encode(collection, COLLECTION_STATES_SLOT)));
        assembly {
            token := val
        }
    }

    function collectionInfo(
        address collection
    )
        public
        view
        returns (
            address fragmentToken,
            address keyIdNft,
            uint256 freeNftLength,
            uint64 activeSafeBoxCnt,
            uint64 nextKeyId,
            uint64 nextActivityId,
            address offerToken
        )
    {
        // bytes32 to type bytes memory
        bytes memory val = _scattering.extsload(keccak256(abi.encode(collection, COLLECTION_STATES_SLOT)), 9);

        assembly {
            fragmentToken := mload(add(val, 0x20))
            keyIdNft := mload(add(val, mul(2, 0x20)))
            freeNftLength := mload(add(val, mul(3, 0x20)))

            let cntVal := mload(add(val, mul(8, 0x20)))
            activeSafeBoxCnt := and(cntVal, MASK_64)
            nextKeyId := and(shr(64, cntVal), MASK_64)
            nextActivityId := and(shr(128, cntVal), MASK_64)
            offerToken := mload(add(val, mul(9, 0x20)))
        }
    }

    function getFreeNftIds(
        address collection,
        uint256 startIdx,
        uint256 size
    ) public view returns (uint256[] memory nftIds) {
        bytes32 collectionSlot = keccak256(abi.encode(collection, COLLECTION_STATES_SLOT));
        bytes32 nftIdsSlot = bytes32(uint256(collectionSlot) + 2);
        uint256 freeNftLength = uint256(_scattering.extsload(nftIdsSlot));

        if (startIdx >= freeNftLength || size == 0) {
            return nftIds;
        }

        uint256 maxLen = freeNftLength - startIdx;
        if (size < maxLen) {
            maxLen = size;
        }

        bytes memory arrVal = _scattering.extsload(
            bytes32(uint256(keccak256(abi.encode(nftIdsSlot))) + startIdx),
            maxLen
        );

        nftIds = new uint256[](maxLen);
        assembly {
            for {
                let i := 0x20
                let end := mul(add(1, maxLen), 0x20)
            } lt(i, end) {
                i := add(i, 0x20)
            } {
                mstore(add(nftIds, i), mload(add(arrVal, i)))
            }
        }
    }

    function getSafeBox(address collection, uint256 nftId) public view returns (SafeBox memory safeBox) {
        bytes32 collectionSlot = keccak256(abi.encode(underlyingCollection(collection), COLLECTION_STATES_SLOT));
        bytes32 safeBoxMapSlot = bytes32(uint256(collectionSlot) + 3);

        uint256 val = uint256(_scattering.extsload(keccak256(abi.encode(nftId, safeBoxMapSlot))));

        safeBox.keyId = uint64(val & MASK_64);
        safeBox.expiryTs = uint32(val >> 64);
        safeBox.owner = address(uint160(val >> 96));
    }

    function getAuction(
        address collection,
        uint256 nftId
    )
        public
        view
        returns (
            uint96 endTime,
            address bidTokenAddress,
            uint128 minimumBid,
            uint128 lastBidAmount,
            address lastBidder,
            address triggerAddress,
            uint64 activityId,
            uint32 feeRateBips,
            AuctionType typ
        )
    {
        bytes32 collectionSlot = keccak256(abi.encode(underlyingCollection(collection), COLLECTION_STATES_SLOT));
        bytes32 auctionMapSlot = bytes32(uint256(collectionSlot) + 4);

        bytes memory val = _scattering.extsload(keccak256(abi.encode(nftId, auctionMapSlot)), 4);

        assembly {
            let slotVal := mload(add(val, 0x20))
            endTime := and(slotVal, MASK_96)
            bidTokenAddress := shr(96, slotVal)

            slotVal := mload(add(val, 0x40))
            minimumBid := and(slotVal, MASK_96)
            triggerAddress := shr(96, slotVal)

            slotVal := mload(add(val, 0x60))
            lastBidAmount := and(slotVal, MASK_96)
            lastBidder := shr(96, slotVal)

            slotVal := mload(add(val, 0x80))
            activityId := and(slotVal, MASK_64)
            feeRateBips := and(shr(64, slotVal), MASK_32)
            typ := and(shr(72, slotVal), 0xFF)
        }
    }

    function getRaffle(
        address collection,
        uint256 nftId
    )
        public
        view
        returns (
            uint48 endTime,
            uint48 maxTickets,
            address token,
            uint96 ticketPrice,
            uint96 collectedFund,
            uint64 activityId,
            address owner,
            uint48 ticketSold,
            uint32 feeRateBips,
            bool isSettling,
            uint256 ticketsArrLen
        )
    {
        bytes32 raffleMapSlot = bytes32(
            uint256(keccak256(abi.encode(underlyingCollection(collection), COLLECTION_STATES_SLOT))) + 5
        );

        bytes memory val = _scattering.extsload(keccak256(abi.encode(nftId, raffleMapSlot)), 4);

        assembly {
            let slotVal := mload(add(val, 0x20))
            endTime := and(slotVal, MASK_48)
            maxTickets := and(shr(48, slotVal), MASK_48)
            token := and(shr(96, slotVal), MASK_160)

            slotVal := mload(add(val, 0x40))
            ticketPrice := and(slotVal, MASK_96)
            collectedFund := and(shr(96, slotVal), MASK_96)
            activityId := and(shr(192, slotVal), MASK_64)

            slotVal := mload(add(val, 0x60))
            owner := and(slotVal, MASK_160)
            ticketSold := and(shr(160, slotVal), MASK_48)
            feeRateBips := and(shr(208, slotVal), MASK_32)
            isSettling := and(shr(240, slotVal), 0xFF)

            ticketsArrLen := mload(add(val, 0x80))
        }
    }

    function getRaffleTicketRecords(
        address collection,
        uint256 nftId,
        uint256 startIdx,
        uint256 size
    ) public view returns (TicketRecord[] memory tickets) {
        bytes32 collectionSlot = keccak256(abi.encode(underlyingCollection(collection), COLLECTION_STATES_SLOT));
        bytes32 raffleMapSlot = bytes32(uint256(collectionSlot) + 5);
        bytes32 ticketRecordsSlot = bytes32(uint256(keccak256(abi.encode(nftId, raffleMapSlot))) + 3);
        uint256 totalRecordsLen = uint256(_scattering.extsload(ticketRecordsSlot));

        if (startIdx >= totalRecordsLen || size == 0) {
            return tickets;
        }

        uint256 maxLen = totalRecordsLen - startIdx;
        if (size < maxLen) {
            maxLen = size;
        }

        bytes memory arrVal = _scattering.extsload(
            bytes32(uint256(keccak256(abi.encode(ticketRecordsSlot))) + startIdx),
            maxLen
        );

        tickets = new TicketRecord[](maxLen);
        for (uint256 i; i < maxLen; ++i) {
            uint256 element;
            assembly {
                element := mload(add(arrVal, mul(add(i, 1), 0x20)))
            }
            tickets[i].buyer = address(uint160(element & MASK_160));
            tickets[i].startIdx = uint48((element >> 160) & MASK_48);
            tickets[i].endIdx = uint48((element >> 208) & MASK_48);
        }
    }

    function getPrivateOffer(
        address collection,
        uint256 nftId
    ) public view returns (address token, uint96 price, address owner, address buyer, uint64 activityId) {
        bytes32 collectionSlot = keccak256(abi.encode(underlyingCollection(collection), COLLECTION_STATES_SLOT));
        bytes32 offerMapSlot = bytes32(uint256(collectionSlot) + 6);

        bytes memory val = _scattering.extsload(keccak256(abi.encode(nftId, offerMapSlot)), 3);

        assembly {
            let slotVal := mload(add(val, 0x20))
            token := and(slotVal, MASK_160)
            price := and(shr(160, slotVal), MASK_96)

            slotVal := mload(add(val, 0x40))
            owner := and(slotVal, MASK_160)

            slotVal := mload(add(val, 0x60))
            buyer := and(slotVal, MASK_160)
            activityId := and(shr(160, slotVal), MASK_64)
        }
    }

    function getOfferFeeRateBips() public pure returns (uint256) {
        return Constants.OFFER_FEE_RATE_BIPS;
    }

    function tokenBalance(address user, address token) public view returns (uint256) {
        bytes32 userSlot = keccak256(abi.encode(user, USER_ACCOUNTS_SLOT));
        bytes32 tokenMapSlot = bytes32(uint256(userSlot));

        bytes32 balance = _scattering.extsload(keccak256(abi.encode(token, tokenMapSlot)));

        return uint256(balance);
    }

    function commissionInfo()
        public
        view
        returns (uint32 trialDays, uint32 commonPoolCommission, uint32 safeBoxCommission)
    {
        uint256 val = uint256(_scattering.extsload(bytes32(TRIAL_DAYS_SLOT)));

        trialDays = uint32(val & MASK_32);
        commonPoolCommission = uint32(val >> 32);
        safeBoxCommission = uint32(val >> 64);
    }

    function getPayment() public view returns (address paymentToken, uint256 paymentAmount) {
        uint256 val = uint256(_scattering.extsload(bytes32(TRIAL_DAYS_SLOT)));
        paymentToken = address(uint160(val >> 96));

        paymentAmount = uint256(_scattering.extsload(bytes32(PAYMENT_AMOUNT_SLOT)));
    }

    function underlyingCollection(address collection) private view returns (address) {
        address underlying = collectionProxy(collection);
        if (underlying == address(0)) {
            return collection;
        }
        return underlying;
    }
}
