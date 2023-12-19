// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "./IMulticall.sol";

interface IScattering is IERC721Receiver, IMulticall {
    /// Admin Operations

    /// @notice Add new collection for Scattering Protocol
    function supportNewCollection(address _originalNFT, address fragmentToken) external;

    /// @notice Add new token which will be used as settlement token in Scattering Protocol
    /// @param addOrRemove `true` means add token, `false` means remove token
    function supportNewToken(address _tokenAddress, bool addOrRemove) external;

    /// @notice set proxy collection config
    /// Note. the `tokenId`s of the proxy collection and underlying collection must be correspond one by one
    /// eg. Paraspace Derivative Token BAYC(nBAYC) -> BAYC
    function setCollectionProxy(address proxyCollection, address underlyingCollection) external;

    /// @notice withdraw platform fee accumulated.
    /// Note. withdraw from `address(this)`'s account.
    function withdrawPlatformFee(address token, uint256 amount) external;

    /// User Operations

    /// @notice User deposits token to the Scattering Contract
    /// @param onBehalfOf deposit token into `onBehalfOf`'s account.(note. the tokens of msg.sender will be transferred)
    function addTokens(address onBehalfOf, address token, uint256 amount) external payable;

    /// @notice User removes token from Scattering Contract
    /// @param receiver who will receive the funds.(note. the token of msg.sender will be transferred)
    function removeTokens(address token, uint256 amount, address receiver) external;

    /// @notice Lock specified `nftIds` into Scattering Safeboxes and receive corresponding Fragment Tokens of the `collection`
    /// @param onBehalfOf who will receive the safebox and fragment tokens.(note. the NFTs of the msg.sender will be transferred)
    function lockNFTs(address collection, uint256[] memory nftIds, address onBehalfOf) external;

    /// @notice Extend the exist safeboxes with longer lock duration with more credit token staked
    function extendKeys(address collection, uint256[] memory nftIds, uint256 newRentalDays) external payable;

    /// @notice Unlock specified `nftIds` which had been locked previously
    ///         sender's wallet should have enough Fragment Tokens of the `collection` which will be burned to redeem the NFTs
    /// @param receiver who will receive the NFTs.
    ///                 note. - The safeboxes of the msg.sender will be removed.
    ///                       - The Fragment Tokens of the msg.sender will be burned.
    function unlockNFTs(address collection, uint256[] memory nftIds, address receiver) external;

    /// @notice Fragment specified `nftIds` into Scattering Vault and receive Fragment Tokens without any locking
    ///         after fragmented, any one has enough Fragment Tokens can redeem there `nftIds`
    /// @param onBehalfOf who will receive the fragment tokens.(note. the NFTs of the msg.sender will be transferred)
    function fragmentNFTs(address collection, uint256[] memory nftIds, address onBehalfOf) external;

    /// @notice Kick expired safeboxes to the vault
    function tidyExpiredNFTs(address collection, uint256[] memory nftIds) external;

    /// @notice Randomly claim `claimCnt` NFTs from Scattering Vault
    ///         sender's wallet should have enough Fragment Tokens of the `collection` which will be burned to redeem the NFTs
    /// @param receiver who will receive the NFTs.
    ///                 note. - the msg.sender will pay the redemption cost.
    ///                       - The Fragment Tokens of the msg.sender will be burned.
    function claimRandomNFT(address collection, uint256 claimCnt, address receiver) external;

    /// @notice Start auctions on specified `nftIds` with an initial bid price(`bidAmount`)
    ///         This kind of auctions will be settled with Scattering Credit Token
    /// @param bidAmount initial bid price
    function initAuctionOnExpiredSafeBoxes(
        address collection,
        uint256[] memory nftIds,
        address bidToken,
        uint256 bidAmount
    ) external;

    /// @notice Start auctions on specified `nftIds` index in the vault with an initial bid price(`bidAmount`)
    ///         This kind of auctions will be settled with Fragment Token of the collection
    /// @param bidAmount initial bid price
    function initAuctionOnVault(
        address collection,
        uint256[] memory vaultIdx,
        address bidToken,
        uint96 bidAmount
    ) external;

    /// @notice Owner starts auctions on his locked Safeboxes
    /// @param token which token should be used to settle auctions(bid, settle)
    /// @param minimumBid minimum bid price when someone place a bid on the auction
    function ownerInitAuctions(address collection, uint256[] memory nftIds, address token, uint256 minimumBid) external;

    //    /// @notice Place a bid on specified `nftId`'s action
    //    /// @param bidAmount bid price
    //    /// @param bidOptionIdx which option used to extend auction expiry and bid price
    //    function placeBidOnAuction(address collection, uint256 nftId, uint256 bidAmount, uint256 bidOptionIdx) external;

    /// @notice Place a bid on specified `nftId`'s action
    /// @param token which token should be transferred to the Scattering for bidding. `0x0` means ETH(native)
    /// @param amountToTransfer how many `token` should to transferred
    function placeBidOnAuction(
        address collection,
        uint256 nftId,
        uint256 bidAmount,
        // uint256 bidOptionIdx,
        address token,
        uint256 amountToTransfer
    ) external payable;

    /// @notice Settle auctions of `nftIds`
    function settleAuctions(address collection, uint256[] memory nftIds) external;

    struct RaffleInitParam {
        address collection;
        uint256[] nftIds;
        /// @notice which token used to buy and settle raffle
        address ticketToken;
        /// @notice price per ticket
        uint96 ticketPrice;
        /// @notice max tickets amount can be sold
        uint32 maxTickets;
        /// @notice durationIdx used to get how long does raffles last
        uint256 duration;
    }

    /// @notice Owner start raffles on locked `nftIds`
    function ownerInitRaffles(RaffleInitParam memory param) external;

    /// @notice Buy `nftId`'s raffle tickets
    /// @param token which token should be transferred to the Scattering for buying. `0x0` means ETH(native)
    /// @param amountToTransfer how many `token` should to transferred
    function buyRaffleTickets(
        address collectionId,
        uint256 nftId,
        uint256 ticketCnt,
        address token,
        uint256 amountToTransfer
    ) external payable;

    /// @notice Settle raffles of `nftIds`
    function settleRaffles(address collectionId, uint256[] memory nftIds) external;

    struct PrivateOfferInitParam {
        address collection;
        uint256[] nftIds;
        /// @notice who will receive the otc offers
        address receiver;
        /// @notice which token used to settle offers
        address token;
        /// @notice price of the offers
        uint96 price;
    }

    /// @notice Owner start private offers(otc) on locked `nftIds`
    function ownerInitPrivateOffers(PrivateOfferInitParam memory param) external;

    /// @notice Owner or Receiver cancel the private offers of `nftIds`
    function cancelPrivateOffers(address collectionId, uint256[] memory nftIds) external;

    //    /// @notice Receiver accept the private offers of `nftIds`
    //    function buyerAcceptPrivateOffers(address collectionId, uint256[] memory nftIds) external;

    /// @notice Receiver accept the private offers of `nftIds`
    /// @param token which token should be transferred to the Scattering for buying. `0x0` means ETH(native)
    /// @param amountToTransfer how many `token` should to transferred
    function buyerAcceptPrivateOffers(
        address collectionId,
        uint256[] memory nftIds,
        address token,
        uint256 amountToTransfer
    ) external payable;

    /// Util operations

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to sload
    /// @return value The value of the slot as bytes32
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to start sloading from
    /// @param nSlots Number of slots to load into return value
    /// @return value The value of the sload-ed slots concatenated as dynamic bytes
    function extsload(bytes32 slot, uint256 nSlots) external view returns (bytes memory value);

    //    function creditToken() external view returns (address);
}
