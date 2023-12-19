// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "../library/ERC721Transfer.sol";

import "../Errors.sol";
import "../Constants.sol";
import "./User.sol";
import "./Helper.sol";
import {SafeBox, CollectionState, AuctionInfo, UserFloorAccount, LockParam} from "./Structs.sol";
import {SafeBoxLib} from "./SafeBox.sol";

import "../interface/IScattering.sol";

library CollectionLib {
    using SafeBoxLib for SafeBox;
    using SafeCast for uint256;
    using UserLib for UserFloorAccount;

    event LockNft(
        address indexed sender,
        address indexed onBehalfOf,
        address indexed collection,
        uint256[] tokenIds,
        uint256[] safeBoxKeys,
        uint256 rentalDays,
        address proxyCollection
    );
    event ExtendKey(address indexed operator, address indexed collection, uint256[] tokenIds, uint256 rentalDays);
    event UnlockNft(
        address indexed operator,
        address indexed receiver,
        address indexed collection,
        uint256[] tokenIds,
        address proxyCollection
    );
    event RemoveExpiredKey(
        address indexed operator,
        address indexed onBehalfOf,
        address indexed collection,
        uint256[] tokenIds,
        uint256[] safeBoxKeys
    );
    event ExpiredNftToVault(address indexed operator, address indexed collection, uint256[] tokenIds);
    event FragmentNft(
        address indexed operator,
        address indexed onBehalfOf,
        address indexed collection,
        uint256[] tokenIds
    );
    event ClaimRandomNft(
        address indexed operator,
        address indexed receiver,
        address indexed collection,
        uint256[] tokenIds
    );

    function fragmentNFTs(
        CollectionState storage collectionState,
        address collection,
        uint256[] memory nftIds,
        address onBehalfOf
    ) public {
        uint256 nftLen = nftIds.length;
        unchecked {
            for (uint256 i; i < nftLen; ++i) {
                collectionState.freeTokenIds.push(nftIds[i]);
            }
        }
        collectionState.fragmentToken.mint(onBehalfOf, Constants.FLOOR_TOKEN_AMOUNT * nftLen);
        ERC721Transfer.safeBatchTransferFrom(collection, msg.sender, address(this), nftIds);

        emit FragmentNft(msg.sender, onBehalfOf, collection, nftIds);
    }

    function lockNfts(
        CollectionState storage collection,
        //        UserFloorAccount storage userAccount,
        LockParam memory param,
        address onBehalfOf
    ) public {
        if (onBehalfOf == address(this)) revert Errors.InvalidParam();
        /// proxy collection only enabled when infinity lock
        // if (param.collection != param.proxyCollection && param.expiryTs != 0) revert Errors.InvalidParam();
        if (param.collection != param.proxyCollection) revert Errors.InvalidParam();

        uint256[] memory nftIds = param.nftIds;
        uint256[] memory newKeys;
        {
            newKeys = _lockNfts(collection, onBehalfOf, nftIds, param.rentalDays);
        }

        /// mint for `onBehalfOf`, transfer from msg.sender
        collection.fragmentToken.mint(onBehalfOf, Constants.FLOOR_TOKEN_AMOUNT * nftIds.length);
        // todo The transfer will fail if it is not the owner, so there is no need to verify that the NFT belongs to this owner
        ERC721Transfer.safeBatchTransferFrom(param.proxyCollection, msg.sender, address(this), nftIds);

        emit LockNft(
            msg.sender,
            onBehalfOf,
            param.collection,
            nftIds,
            newKeys,
            param.rentalDays,
            param.proxyCollection
        );
    }

    function _lockNfts(
        CollectionState storage collectionState,
        //        CollectionAccount storage account,
        address onBehalfOf,
        uint256[] memory nftIds,
        uint256 rentalDays
    ) private returns (uint256[] memory) {
        /// @dev `keys` used to log info, we just compact its fields into one 256 bits number
        uint256[] memory keys = new uint256[](nftIds.length);

        for (uint256 idx; idx < nftIds.length; ) {
            uint64 keyId = Helper.generateNextKeyId(collectionState);
            uint256 expiryTs = block.timestamp + rentalDays * 1 days;
            addSafeBox(
                collectionState,
                nftIds[idx],
                SafeBox({keyId: keyId, expiryTs: uint32(expiryTs), owner: onBehalfOf})
            );

            // keys[idx] = SafeBoxLib.encodeSafeBoxKey(key);
            keys[idx] = uint256(keyId);

            unchecked {
                ++idx;
            }
        }

        return keys;
    }

    function unlockNfts(
        CollectionState storage collection,
        //        UserFloorAccount storage userAccount,
        //        UserFloorAccount storage userAccount,
        address proxyCollection,
        address collectionId,
        uint256[] memory nftIds,
        address receiver
    ) public {
        _unlockNfts(collection, nftIds);

        /// @dev if the receiver is the contract self, then unlock the safeboxes and dump the NFTs to the vault
        if (receiver == address(this)) {
            uint256 nftLen = nftIds.length;
            for (uint256 i; i < nftLen; ) {
                collection.freeTokenIds.push(nftIds[i]);
                unchecked {
                    ++i;
                }
            }
            emit FragmentNft(msg.sender, msg.sender, collectionId, nftIds);
        } else {
            collection.fragmentToken.burn(msg.sender, Constants.FLOOR_TOKEN_AMOUNT * nftIds.length);
            ERC721Transfer.safeBatchTransferFrom(proxyCollection, address(this), receiver, nftIds);
        }

        emit UnlockNft(msg.sender, receiver, collectionId, nftIds, proxyCollection);
    }

    function _unlockNfts(CollectionState storage collectionState, uint256[] memory nftIds) private {
        for (uint256 i; i < nftIds.length; ) {
            uint256 nftId = nftIds[i];

            if (Helper.hasActiveActivities(collectionState, nftId)) revert Errors.NftHasActiveActivities();

            // SafeBox storage safeBox = Helper.useSafeBoxAndKey(collectionState, msg.sender, nftId);
            Helper.useSafeBoxAndKey(collectionState, msg.sender, nftId);

            removeSafeBox(collectionState, nftId);

            unchecked {
                ++i;
            }
        }
    }

    function extendLockingForKeys(
        CollectionState storage collection,
        //        UserFloorAccount storage userAccount,
        LockParam memory param,
        address onBehalfOf
    ) public {
        {
            _extendLockingForKeys(collection, param.nftIds, param.rentalDays, onBehalfOf);
        }

        emit ExtendKey(msg.sender, param.collection, param.nftIds, param.rentalDays);
    }

    function _extendLockingForKeys(
        CollectionState storage collectionState,
        //        CollectionAccount storage userCollectionAccount,
        uint256[] memory nftIds,
        uint256 newRentalDays,
        address onBehalfOf
    ) private returns (uint256[] memory) {
        /// @dev `keys` used to log info, we just compact its fields into one 256 bits number
        uint256[] memory keys = new uint256[](nftIds.length);

        for (uint256 idx; idx < nftIds.length; ) {
            if (Helper.hasActiveActivities(collectionState, nftIds[idx])) revert Errors.NftHasActiveActivities();

            SafeBox storage safeBox = Helper.useSafeBoxAndKey(collectionState, onBehalfOf, nftIds[idx]);

            uint256 newExpiryTs = safeBox.expiryTs + newRentalDays * 1 days;
            safeBox.expiryTs = uint32(newExpiryTs);

            //keys[idx] = SafeBoxLib.encodeSafeBoxKey(safeBoxKey);
            keys[idx] = safeBox.keyId;

            unchecked {
                ++idx;
            }
        }

        return keys;
    }

    function tidyExpiredNFTs(CollectionState storage collection, uint256[] memory nftIds, address collectionId) public {
        uint256 nftLen = nftIds.length;

        for (uint256 i; i < nftLen; ) {
            uint256 nftId = nftIds[i];
            SafeBox storage safeBox = Helper.useSafeBox(collection, nftId);
            if (!safeBox.isSafeBoxExpired()) revert Errors.SafeBoxHasNotExpire();
            // todo If auctions are enabled in the future, this next line of code should be retained
            if (!Helper.isAuctionPeriodOver(safeBox)) revert Errors.AuctionHasNotCompleted();

            /// remove expired safeBox, and dump it to vault
            removeSafeBox(collection, nftId);
            collection.freeTokenIds.push(nftId);

            unchecked {
                ++i;
            }
        }

        emit ExpiredNftToVault(msg.sender, collectionId, nftIds);
    }

    function claimRandomNFT(
        CollectionState storage collection,
        //address creditToken,
        address collectionId,
        uint256 claimCnt,
        address receiver
    ) public {
        //creditToken;
        if (claimCnt == 0 || collection.freeTokenIds.length < claimCnt) revert Errors.ClaimableNftInsufficient();

        uint256 freeAmount = collection.freeTokenIds.length;
        uint256 totalManaged = collection.activeSafeBoxCnt + freeAmount;

        uint256[] memory selectedTokenIds = new uint256[](claimCnt);

        while (claimCnt > 0) {
            /// just compute a deterministic random number
            uint256 chosenNftIdx = uint256(
                // https://docs.arbitrum.io/for-devs/concepts/differences-between-arbitrum-ethereum/solidity-support
                // keccak256(abi.encodePacked(block.timestamp, block.prevrandao, totalManaged))
                keccak256(abi.encodePacked(block.timestamp, block.number, blockhash(block.number - 1), totalManaged))
            ) % collection.freeTokenIds.length;

            unchecked {
                --claimCnt;
                --totalManaged;
                --freeAmount;
            }

            selectedTokenIds[claimCnt] = collection.freeTokenIds[chosenNftIdx];

            collection.freeTokenIds[chosenNftIdx] = collection.freeTokenIds[collection.freeTokenIds.length - 1];
            collection.freeTokenIds.pop();
        }

        // userAccount.transferToken(userAccounts[address(this)], creditToken, totalCreditCost, true);
        collection.fragmentToken.burn(msg.sender, Constants.FLOOR_TOKEN_AMOUNT * selectedTokenIds.length);
        ERC721Transfer.safeBatchTransferFrom(collectionId, address(this), receiver, selectedTokenIds);

        emit ClaimRandomNft(msg.sender, receiver, collectionId, selectedTokenIds);
    }

    function addSafeBox(CollectionState storage collectionState, uint256 nftId, SafeBox memory safeBox) internal {
        if (collectionState.safeBoxes[nftId].keyId > 0) revert Errors.SafeBoxAlreadyExist();
        collectionState.safeBoxes[nftId] = safeBox;
        ++collectionState.activeSafeBoxCnt;
    }

    function removeSafeBox(CollectionState storage collectionState, uint256 nftId) internal {
        delete collectionState.safeBoxes[nftId];
        --collectionState.activeSafeBoxCnt;
    }

    function transferSafeBox(CollectionState storage collectionState, SafeBox storage safeBox, address to) internal {
        // Shh - currently unused
        collectionState.keyIdNft;
        //address from=safeBox.owner;
        safeBox.owner = to;
    }
}
