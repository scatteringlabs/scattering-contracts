// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {VRFCoordinatorV2Interface} from "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "chainlink/v0.8/vrf/VRFConsumerBaseV2.sol";
import "./interface/IScattering.sol";
import "./interface/IScatteringEvent.sol";
import "./interface/IFragmentToken.sol";

import "./logic/User.sol";
import "./logic/Collection.sol";
import "./logic/Auction.sol";
import "./logic/Raffle.sol";
import "./logic/PrivateOffer.sol";
import {CollectionState, SafeBox, AuctionInfo, RaffleInfo, PrivateOffer, UserFloorAccount} from "./logic/Structs.sol";
import "./Multicall.sol";
import "./Errors.sol";
import "./library/CurrencyTransfer.sol";

/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Scattering is
    IScattering,
    IScatteringEvent,
    Multicall,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    VRFConsumerBaseV2
{
    using CollectionLib for CollectionState;
    using AuctionLib for CollectionState;
    using RaffleLib for CollectionState;
    using PrivateOfferLib for CollectionState;
    using UserLib for UserFloorAccount;

    struct RandomRequestInfo {
        uint96 typ;
        address collection;
        bytes data;
    }

    /// Information related to Chainlink VRF Randomness Oracle.

    /// The keyhash, which is network dependent.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bytes32 internal immutable keyHash;
    /// Subscription Id, need to get from the Chainlink UI.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint64 internal immutable subId;
    /// Chainlink VRF Coordinator.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    VRFCoordinatorV2Interface internal immutable COORDINATOR;

    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    /// @notice If set to true, this will suspend the functions fragmentNFTs, initAuctionOnVault,
    /// initAuctionOnExpiredSafeBoxes, ownerInitAuctions, and ownerInitRaffles.
    bool internal constant FUNCTION_DISABLED = true;

    /// A mapping from VRF request Id to raffle.
    mapping(uint256 => RandomRequestInfo) internal randomnessRequestToReceiver;

    /// A mapping from collection address to `CollectionState`.
    mapping(address => CollectionState) internal collectionStates;

    /// A mapping from user address to the `UserFloorAccount`s.
    mapping(address => UserFloorAccount) internal userFloorAccounts;

    /// A mapping of supported ERC-20 token.
    mapping(address => bool) internal supportedTokens;

    /// A mapping from Proxy Collection(wrapped) to underlying Collection.
    /// eg. Paraspace Derivative Token BAYC(nBAYC) -> BAYC
    /// Note. we only use proxy collection to transfer NFTs,
    ///       all other operations should use underlying Collection.(State, Log, CollectionAccount)
    ///       proxy collection has not `CollectionState`, but use underlying collection's state.
    ///       proxy collection only is used to lock infinitely.
    ///       `fragmentNFTs` and `claimRandomNFT` don't support proxy collection
    mapping(address => address) internal collectionProxy;

    uint32 internal trialDays; // trial period in days
    uint32 internal commonPoolCommission; //  the uint32 type can easily represent the number 10000
    uint32 internal safeBoxCommission; //  the uint32 type can easily represent the number 10000
    address internal paymentToken; //  Extend the validity period payment token. If it is Native, use address(0)
    uint256 internal paymentAmount; // Extend the validity period payment amount

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bytes32 _keyHash, uint64 _subId, address _vrfCoordinator) payable VRFConsumerBaseV2(_vrfCoordinator) {
        keyHash = _keyHash;
        subId = _subId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);

        _disableInitializers();
    }

    /// required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @dev just declare this as payable to reduce gas and bytecode
    function initialize(address _admin, address _monitor, uint32 _trialDays) external payable initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MONITOR_ROLE, _monitor);
        trialDays = _trialDays;
    }

    function setTrialDays(uint32 _trialDays) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_trialDays > 30) {
            revert Errors.InvalidParam();
        }
        trialDays = _trialDays;
    }

    // @notice set the payment token and the payment amount for extending the expiry of the nft
    function setPaymentParam(address _paymentToken, uint256 _paymentAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_paymentAmount == 0) {
            revert Errors.InvalidParam();
        }
        paymentToken = _paymentToken;
        paymentAmount = _paymentAmount;
    }

    function setCommonPoolCommission(uint32 _commonPoolCommission) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_commonPoolCommission > 10_000) {
            revert Errors.InvalidParam();
        }
        commonPoolCommission = _commonPoolCommission;
    }

    function setSafeBoxCommission(uint32 _safeBoxCommission) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_safeBoxCommission > 10_000) {
            revert Errors.InvalidParam();
        }
        safeBoxCommission = _safeBoxCommission;
    }

    function pause() external onlyRole(MONITOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function supportNewCollection(address _originalNFT, address _fragmentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CollectionState storage collection = collectionStates[_originalNFT];
        if (collection.nextKeyId > 0) revert Errors.NftCollectionAlreadySupported();

        collection.nextKeyId = 1;
        collection.nextActivityId = 1;
        collection.fragmentToken = IFragmentToken(_fragmentToken);

        emit NewCollectionSupported(_originalNFT, _fragmentToken);
    }

    function setNewOfferToken(address _originalNFT, address _offerToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        CollectionState storage collectionState = _useCollectionState(_originalNFT);
        collectionState.offerToken = _offerToken;
        emit OfferTokenUpdated(_originalNFT, _offerToken);
    }

    // @notice supported tokens can be used for offer, auction, and raffle
    function supportNewToken(address _token, bool addOrRemove) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (supportedTokens[_token] == addOrRemove) {
            return;
        } else {
            /// true - add
            /// false - remove
            supportedTokens[_token] = addOrRemove;
            emit UpdateTokenSupported(_token, addOrRemove);
        }
    }

    function setCollectionProxy(address proxyCollection, address underlying) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (collectionProxy[proxyCollection] == underlying) {
            return;
        } else {
            collectionProxy[proxyCollection] = underlying;
            emit ProxyCollectionChanged(proxyCollection, underlying);
        }
    }

    function withdrawPlatformFee(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        /// track platform fee with account, only can withdraw fee accumulated during tx.
        /// no need to check credit token balance for the account.
        UserFloorAccount storage userFloorAccount = userFloorAccounts[address(this)];
        userFloorAccount.withdraw(msg.sender, token, amount, false);
    }

    function addTokens(address onBehalfOf, address token, uint256 amount) public payable whenNotPaused {
        _addSupportTokens(onBehalfOf, token, amount);
    }

    // @notice only supported tokens can be transferred in
    function _addSupportTokens(address onBehalfOf, address token, uint256 amount) internal {
        _mustSupportedToken(token);
        _addTokensInternal(onBehalfOf, token, amount);
    }

    // @notice there is no restriction here on whether the token is a supported token
    function _addTokensInternal(address onBehalfOf, address token, uint256 amount) internal {
        UserFloorAccount storage userFloorAccount = userFloorAccounts[onBehalfOf];
        userFloorAccount.deposit(onBehalfOf, token, amount, false);
    }

    function removeTokens(address token, uint256 amount, address receiver) external whenNotPaused {
        UserFloorAccount storage userFloorAccount = userFloorAccounts[msg.sender];
        userFloorAccount.withdraw(receiver, token, amount, false);
    }

    /**
     * @notice Lock specified `nftIds` into Scattering Safeboxes and receive corresponding Fragment Tokens of the `collection`
     * @param onBehalfOf who will receive the safebox and fragment tokens.(note. the NFTs of the msg.sender will be transferred)
     */
    function lockNFTs(
        address collection,
        uint256[] memory nftIds,
        address onBehalfOf
    ) external nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        collectionState.lockNfts(
            LockParam({proxyCollection: collection, collection: underlying, nftIds: nftIds, rentalDays: trialDays}),
            onBehalfOf
        );
    }

    function unlockNFTs(
        address collection,
        uint256[] memory nftIds,
        address receiver
    ) external nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        // Pay the commission to the platform; verify safeBoxCommission and nftLengths(_mustValidNftIds already valid) is greater than zero
        if (safeBoxCommission > 0) {
            uint256 totalCommission = (Constants.FLOOR_TOKEN_AMOUNT * nftIds.length * safeBoxCommission) / 10_000;
            _addTokensInternal(address(this), address(collectionState.fragmentToken), totalCommission);
        }

        collectionState.unlockNfts(collection, underlying, nftIds, receiver);
    }

    function extendKeys(
        address collection,
        uint256[] memory nftIds,
        uint256 newRentalDays
    ) external payable nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);
        _mustValidRentalDays(newRentalDays);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        // verify paymentAmount and nftLengths(_mustValidNftIds already valid) is greater than zero
        if (paymentAmount == 0) {
            revert Errors.InvalidParam();
        }
        uint256 totalPayoutAmount = paymentAmount * newRentalDays * nftIds.length;
        _addTokensInternal(address(this), paymentToken, totalPayoutAmount);

        collectionState.extendLockingForKeys(
            //            userFloorAccounts[msg.sender],
            LockParam({proxyCollection: collection, collection: underlying, nftIds: nftIds, rentalDays: newRentalDays}),
            msg.sender // todo This can be extended here to support renewing keys for other users.
        );
    }

    function tidyExpiredNFTs(address collection, uint256[] memory nftIds) external whenNotPaused {
        _mustValidNftIds(nftIds);
        /// expired safeBoxes must not be collection
        CollectionState storage collectionState = _useCollectionState(collection);
        collectionState.tidyExpiredNFTs(nftIds, collection);
    }

    function fragmentNFTs(
        address collection,
        uint256[] memory nftIds,
        address onBehalfOf
    ) external nonReentrant whenNotPaused {
        if (FUNCTION_DISABLED) {
            _disabledFunction();
        }
        _mustValidNftIds(nftIds);
        CollectionState storage collectionState = _useCollectionState(collection);

        collectionState.fragmentNFTs(collection, nftIds, onBehalfOf);
    }

    function claimRandomNFT(
        address collection,
        uint256 claimCnt,
        address receiver
    ) external nonReentrant whenNotPaused {
        if (receiver == address(this)) {
            revert Errors.InvalidParam();
        }
        CollectionState storage collectionState = _useCollectionState(collection);
        // verify paymentAmount and claimCnt is greater than zero
        if (commonPoolCommission > 0 && claimCnt > 0) {
            uint256 totalCommission = (Constants.FLOOR_TOKEN_AMOUNT * claimCnt * commonPoolCommission) / 10_000;
            _addTokensInternal(address(this), address(collectionState.fragmentToken), totalCommission);
        }
        collectionState.claimRandomNFT(collection, claimCnt, receiver);
    }

    function initAuctionOnVault(
        address collection,
        uint256[] memory vaultIdx,
        address bidToken,
        uint96 bidAmount
    ) external nonReentrant whenNotPaused {
        if (FUNCTION_DISABLED) {
            _disabledFunction();
        }
        _mustValidNftIds(vaultIdx);
        _mustValidTransferAmount(bidToken, bidAmount);
        _mustSupportedToken(bidToken);

        CollectionState storage collectionState = _useCollectionState(collection);
        collectionState.initAuctionOnVault(userFloorAccounts, collection, vaultIdx, bidToken, bidAmount);
    }

    function initAuctionOnExpiredSafeBoxes(
        address collection,
        uint256[] memory nftIds,
        address bidToken,
        uint256 bidAmount
    ) external nonReentrant whenNotPaused {
        if (FUNCTION_DISABLED) {
            _disabledFunction();
        }
        _mustValidNftIds(nftIds);
        _mustValidTransferAmount(bidToken, bidAmount);
        _mustSupportedToken(bidToken);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        collectionState.initAuctionOnExpiredSafeBoxes(userFloorAccounts, underlying, nftIds, bidToken, bidAmount);
    }

    function ownerInitAuctions(
        address collection,
        uint256[] memory nftIds,
        address token,
        uint256 minimumBid
    ) external nonReentrant whenNotPaused {
        if (FUNCTION_DISABLED) {
            _disabledFunction();
        }
        _mustValidNftIds(nftIds);
        _mustValidTransferAmount(token, minimumBid);
        _mustSupportedToken(token);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        collectionState.ownerInitAuctions(userFloorAccounts, /* creditToken,*/ underlying, nftIds, token, minimumBid);
    }

    function placeBidOnAuction(
        address collection,
        uint256 nftId,
        uint256 bidAmount,
        address token,
        uint256 amountToTransfer
    ) external payable nonReentrant whenNotPaused {
        _addSupportTokens(msg.sender, token, amountToTransfer);

        /// we don't check whether msg.value is equal to bidAmount, as we utility all currency balance of user account,
        /// it will be reverted if there is no enough balance to pay the required bid.
        _placeBidOnAuction(collection, nftId, bidAmount /*, bidOptionIdx*/);
    }

    function _placeBidOnAuction(address collection, uint256 nftId, uint256 bidAmount) internal {
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        collectionState.placeBidOnAuction(userFloorAccounts, underlying, nftId, bidAmount);
    }

    function settleAuctions(address collection, uint256[] memory nftIds) external nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collection);
        collectionState.settleAuctions(userFloorAccounts, underlying, nftIds);
    }

    function ownerInitRaffles(RaffleInitParam memory param) external nonReentrant whenNotPaused {
        if (FUNCTION_DISABLED) {
            _disabledFunction();
        }
        _mustValidNftIds(param.nftIds);
        _mustValidTransferAmount(param.ticketToken, param.ticketPrice);
        _mustSupportedToken(param.ticketToken);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(param.collection);
        param.collection = underlying;

        collectionState.ownerInitRaffles(userFloorAccounts, param /*, creditToken*/);
    }

    function buyRaffleTickets(
        address collectionId,
        uint256 nftId,
        uint256 ticketCnt,
        address token,
        uint256 amountToTransfer
    ) external payable nonReentrant whenNotPaused {
        _addSupportTokens(msg.sender, token, amountToTransfer);
        _buyRaffleTicketsInternal(collectionId, nftId, ticketCnt);
    }

    function _buyRaffleTicketsInternal(address collectionId, uint256 nftId, uint256 ticketCnt) internal {
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collectionId);

        collectionState.buyRaffleTickets(userFloorAccounts, /* creditToken,*/ underlying, nftId, ticketCnt);
    }

    function settleRaffles(address collectionId, uint256[] memory nftIds) external nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);
        if (nftIds.length > 8) revert Errors.InvalidParam();
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collectionId);

        (bytes memory toSettleNftIds, uint256 len) = collectionState.prepareSettleRaffles(nftIds);
        if (len > 0) {
            uint256 requestId = COORDINATOR.requestRandomWords(keyHash, subId, 3, 800_000, uint32(len));
            randomnessRequestToReceiver[requestId] = RandomRequestInfo({
                typ: 1,
                collection: underlying,
                data: toSettleNftIds
            });
        }
    }

    function _completeSettleRaffles(address collectionId, bytes memory data, uint256[] memory randoms) private {
        CollectionState storage collection = collectionStates[collectionId];
        collection.settleRaffles(userFloorAccounts, collectionId, data, randoms);
    }

    function ownerInitPrivateOffers(PrivateOfferInitParam memory param) external nonReentrant whenNotPaused {
        _mustValidNftIds(param.nftIds);
        _mustValidTransferAmount(param.token, param.price);
        // a comparison is made below, so next line can be removed
        //  _mustSupportedToken(param.token);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(param.collection);
        if (collectionState.offerToken != param.token) {
            revert Errors.TokenNotSupported();
        }
        param.collection = underlying;
        collectionState.ownerInitPrivateOffers(/*userFloorAccounts,  creditToken,*/ param);
    }

    function cancelPrivateOffers(address collectionId, uint256[] memory nftIds) external whenNotPaused {
        _mustValidNftIds(nftIds);
        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collectionId);
        collectionState.removePrivateOffers(underlying, nftIds);
    }

    function buyerAcceptPrivateOffers(
        address collectionId,
        uint256[] memory nftIds,
        address token,
        uint256 amountToTransfer
    ) external payable nonReentrant whenNotPaused {
        _mustValidNftIds(nftIds);
        _addSupportTokens(msg.sender, token, amountToTransfer);

        (CollectionState storage collectionState, address underlying) = _useUnderlyingCollectionState(collectionId);
        collectionState.buyerAcceptPrivateOffers(userFloorAccounts, underlying, nftIds /*, creditToken*/);
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _useUnderlyingCollectionState(
        address collectionId
    ) private view returns (CollectionState storage, address) {
        address underlying = collectionProxy[collectionId];
        if (underlying == address(0)) {
            underlying = collectionId;
        }

        return (_useCollectionState(underlying), underlying);
    }

    function _useCollectionState(address collectionId) private view returns (CollectionState storage) {
        CollectionState storage collection = collectionStates[collectionId];
        if (collection.nextKeyId == 0) revert Errors.NftCollectionNotSupported();
        return collection;
    }

    function _disabledFunction() private pure {
        revert Errors.DisabledFunction();
    }

    function _mustSupportedToken(address token) private view {
        if (!supportedTokens[token]) revert Errors.TokenNotSupported();
    }

    // @notice the minimum amount for transfer is 0.0001 token;
    // if the decimal places are less than 4, the minimum transfer amount is 1 token
    function _mustValidTransferAmount(address token, uint256 amount) private view {
        uint8 decimals;
        if (token == CurrencyTransfer.NATIVE) {
            decimals = 18;
        } else {
            decimals = IERC20Metadata(token).decimals();
        }
        uint256 minAmount = 10 ** (decimals > 3 ? 4 : 0);
        if (amount < minAmount) {
            revert Errors.AmountTooSmall(minAmount, amount);
        }
    }

    function _mustValidNftIds(uint256[] memory nftIds) private pure {
        if (nftIds.length == 0) revert Errors.InvalidParam();

        /// nftIds should be ordered and there should be no duplicate elements.
        for (uint256 i = 1; i < nftIds.length; ) {
            unchecked {
                if (nftIds[i] <= nftIds[i - 1]) {
                    revert Errors.InvalidParam();
                }
                ++i;
            }
        }
    }

    // @notice ensure that the maximum value does not exceed uint32 to prevent data overflow; setting it to uint24 should be sufficient
    function _mustValidRentalDays(uint256 rentalDays) private pure {
        if (rentalDays == 0 || rentalDays > type(uint24).max) revert Errors.InvalidParam();
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        RandomRequestInfo storage info = randomnessRequestToReceiver[requestId];

        _completeSettleRaffles(info.collection, info.data, randomWords);

        delete randomnessRequestToReceiver[requestId];
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        bytes memory value = new bytes(nSlots << 5);

        /// @solidity memory-safe-assembly
        assembly {
            for {
                let i := 0
            } lt(i, nSlots) {
                i := add(i, 1)
            } {
                mstore(add(value, shl(5, add(i, 1))), sload(add(startSlot, i)))
            }
        }

        return value;
    }

    receive() external payable {
        _addSupportTokens(msg.sender, CurrencyTransfer.NATIVE, msg.value);
    }
}
