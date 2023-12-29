// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interface/IArbSys.sol";

library Constants {
    /// @notice Scattering protocol
    /// @dev fragment token amount of 1 NFT (with 18 decimals)
    uint256 public constant FLOOR_TOKEN_AMOUNT = 10_000 ether;

    /// @notice Auction Config
    uint256 public constant FREE_AUCTION_PERIOD = 24 hours;
    uint256 public constant AUCTION_INITIAL_PERIODS = 24 hours;
    uint256 public constant AUCTION_COMPLETE_GRACE_PERIODS = 2 days;
    /// @dev minimum bid per NFT when someone starts auction on expired safebox
    uint256 public constant AUCTION_ON_EXPIRED_MINIMUM_BID = 1000 ether;
    /// @dev minimum bid per NFT when someone starts auction on vault
    uint256 public constant AUCTION_ON_VAULT_MINIMUM_BID = 10000 ether;
    /// @dev admin fee charged per NFT when someone starts auction on expired safebox
    uint256 public constant AUCTION_ON_EXPIRED_SAFEBOX_COST = 0;
    /// @dev admin fee charged per NFT when owner starts auction on himself safebox
    uint256 public constant AUCTION_COST = 100 ether;

    /// @notice Raffle Config
    uint256 public constant RAFFLE_COST = 500 ether;
    uint256 public constant RAFFLE_COMPLETE_GRACE_PERIODS = 2 days;

    /// @notice Private offer Config
    uint256 public constant PRIVATE_OFFER_DURATION = 24 hours;
    uint256 public constant PRIVATE_OFFER_COMPLETE_GRACE_DURATION = 2 days;
    uint256 public constant PRIVATE_OFFER_COST = 0;

    /// @notice Activities Fee Rate

    /// @notice Fee rate used to distribute funds that collected from Auctions on expired safeboxes.
    /// these auction would be settled using credit token
    uint256 public constant FREE_AUCTION_FEE_RATE_BIPS = 2000; // 20%
    /// @notice Fee rate settled with credit token
    uint256 public constant CREDIT_FEE_RATE_BIPS = 150; // 2%
    /// @notice Fee rate settled with specified token
    uint256 public constant SPEC_FEE_RATE_BIPS = 300; // 3%
    /// @notice Fee rate settled with all other tokens
    uint256 public constant COMMON_FEE_RATE_BIPS = 500; // 5%

    // @notice The fee rate charged to the seller when accepting offer
    uint256 public constant OFFER_FEE_RATE_BIPS = 200; // 2%
    /// @notice Fee rate for redemption from safeBox
    uint256 public constant SAFE_BOX_FEE_RATE_BIPS = 500; // 5%
    /// @notice Fee rate for redemption from common pool
    uint256 public constant COMMON_POOL_FEE_RATE_BIPS = 200; // 2%

    /// @notice Collection Config

    /// @notice The number of free trial days for safeBox
    uint256 public constant TRIAL_DAYS = 3; // 3 days

    /// @notice Arbitrum Config

    // https://github.com/OffchainLabs/nitro/blob/v2.0.14/contracts/src/precompiles/ArbSys.sol#L10
    // https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/ChainSpecificUtil.sol
    uint256 private constant ARB_MAINNET_CHAIN_ID = 42161;
    uint256 private constant ARB_GOERLI_TESTNET_CHAIN_ID = 421613;
    uint256 private constant ARB_SEPOLIA_TESTNET_CHAIN_ID = 421614;
    IArbSys private constant ARBSYS = IArbSys(address(100));

    struct AuctionBidOption {
        uint256 extendDurationSecs;
        uint256 minimumRaisePct;
    }

    function getBidOption() internal pure returns (AuctionBidOption memory) {
        return AuctionBidOption({extendDurationSecs: 1 hours, minimumRaisePct: 10});
    }

    function raffleDurations() internal pure returns (uint256 duration) {
        return 2 days;
    }

    /**
     * @notice Returns the blockhash for the given blockNumber.
     * @notice When on a known Arbitrum chain, it uses ArbSys.arbBlockHash to get the blockhash.
     * @notice Otherwise, it uses the blockhash opcode.
     * @notice Note that the blockhash opcode will return the L2 blockhash on Optimism.
     */
    function _getBlockHash(uint256 blockNumber) internal view returns (bytes32) {
        uint256 chainid = block.chainid;
        if (_isArbitrumChainId(chainid)) {
            return ARBSYS.arbBlockHash(blockNumber);
        }

        return blockhash(blockNumber);
    }

    /**
     * @notice Returns the block number of the current block.
     * @notice When on a known Arbitrum chain, it uses ArbSys.arbBlockNumber to get the block number.
     * @notice Otherwise, it uses the block.number opcode.
     * @notice Note that the block.number opcode will return the L2 block number on Optimism.
     */
    function _getBlockNumber() internal view returns (uint256) {
        uint256 chainid = block.chainid;
        if (_isArbitrumChainId(chainid)) {
            return ARBSYS.arbBlockNumber();
        }

        return block.number;
    }

    /**
     * @notice Return true if and only if the provided chain ID is an Arbitrum chain ID.
     */
    function _isArbitrumChainId(uint256 chainId) internal pure returns (bool) {
        return
            chainId == ARB_MAINNET_CHAIN_ID ||
            chainId == ARB_GOERLI_TESTNET_CHAIN_ID ||
            chainId == ARB_SEPOLIA_TESTNET_CHAIN_ID;
    }
}
