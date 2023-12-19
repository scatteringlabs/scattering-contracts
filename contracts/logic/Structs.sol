// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interface/IFragmentToken.sol";

struct SafeBox {
    /// Either matching a key OR Constants.SAFEBOX_KEY_NOTATION meaning temporarily
    /// held by a bidder in auction.
    uint64 keyId;
    /// The timestamp that the safe box expires.
    uint32 expiryTs;
    /// The owner of the safebox. It maybe outdated due to expiry
    address owner;
}

struct PrivateOffer {
    /// which token used to accept the offer
    address token;
    /// price of the offer
    uint96 price;
    address owner;
    /// who should receive the offer
    address buyer;
    uint64 activityId;
}

enum AuctionType {
    Owned,
    Expired,
    Vault
}

struct AuctionInfo {
    /// The end time for the auction.
    uint96 endTime;
    /// Bid token address.
    address bidTokenAddress;
    /// Minimum Bid.
    uint96 minimumBid;
    /// The person who trigger the auction at the beginning.
    address triggerAddress;
    uint96 lastBidAmount;
    address lastBidder;
    uint64 activityId;
    uint32 feeRateBips;
    AuctionType typ;
}

struct TicketRecord {
    /// who buy the tickets
    address buyer;
    /// Start index of tickets
    /// [startIdx, endIdx)
    uint48 startIdx;
    /// End index of tickets
    uint48 endIdx;
}

struct RaffleInfo {
    /// raffle end time
    uint48 endTime;
    /// max tickets amount the raffle can sell
    uint48 maxTickets;
    /// which token used to buy the raffle tickets
    address token;
    /// price per ticket
    uint96 ticketPrice;
    /// total funds collected by selling tickets
    uint96 collectedFund;
    uint64 activityId;
    address owner;
    /// total sold tickets amount
    uint48 ticketSold;
    uint32 feeRateBips;
    /// whether the raffle is being settling
    bool isSettling;
    /// tickets sold records
    TicketRecord[] tickets;
}

struct CollectionState {
    /// The address of the Scattering Token corresponding to the NFTs.
    IFragmentToken fragmentToken;
    address keyIdNft;
    /// Stores all of the NFTs that has been fragmented but *without* locked up limit.
    uint256[] freeTokenIds;
    /// Huge map for all the `SafeBox`es in one collection.
    mapping(uint256 => SafeBox) safeBoxes;
    /// Stores all the ongoing auctions: nftId => `AuctionInfo`.
    mapping(uint256 => AuctionInfo) activeAuctions;
    /// Stores all the ongoing raffles: nftId => `RaffleInfo`.
    mapping(uint256 => RaffleInfo) activeRaffles;
    /// Stores all the ongoing private offers: nftId => `PrivateOffer`.
    mapping(uint256 => PrivateOffer) activePrivateOffers;
    // @notice will be stored in the slot from right to left in sequence
    /// Active Safe Box Count.
    uint64 activeSafeBoxCnt;
    /// Next Key Id. This should start from 1, we treat key id `SafeboxLib.SAFEBOX_KEY_NOTATION` as temporarily
    /// being used for activities(auction/raffle).
    uint64 nextKeyId;
    /// Next Activity Id. This should start from 1
    uint64 nextActivityId;
    address offerToken;
}

struct UserFloorAccount {
    mapping(address => uint256) tokenAmounts;
}

/// Internal Structure
struct LockParam {
    address proxyCollection;
    address collection;
    uint256[] nftIds;
    uint256 rentalDays;
}

struct FeeParam {
    uint256 safeBoxCommission;
    uint256 commonPoolCommission;
}
