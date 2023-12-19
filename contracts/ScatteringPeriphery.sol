// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

import {IScattering} from "./interface/IScattering.sol";
import {CurrencyTransfer} from "./library/CurrencyTransfer.sol";
import {ERC721Transfer} from "./library/ERC721Transfer.sol";
import {TicketRecord, SafeBox} from "./logic/Structs.sol";
import "./logic/SafeBox.sol";
import "./Errors.sol";
import "./Constants.sol";
import {ScatteringGetter} from "./ScatteringGetter.sol";
import "./Multicall.sol";
import "./interface/IWETH9.sol";

contract ScatteringPeriphery is
    ScatteringGetter,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IERC721Receiver,
    Multicall
{
    error NotRouterOrWETH9();
    error InsufficientWETH9();

    address public uniswapRouter;
    address public WETH9;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address scattering_,
        address uniswapV3Router_,
        address weth9_,
        address owner_
    ) public initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _transferOwnership(owner_);

        _scattering = IScattering(scattering_);
        uniswapRouter = uniswapV3Router_;
        WETH9 = weth9_;
    }

    function fragmentAndSell(
        address collection,
        uint256[] calldata tokenIds,
        bool unwrapWETH,
        ISwapRouter.ExactInputParams memory swapParam
    ) external payable nonReentrant returns (uint256 swapOut) {
        (, uint32 commonPoolCommission, ) = commissionInfo();
        // nftLen * FLOOR_TOKEN_AMOUNT * (10000+200)/10000
        uint256 fragmentTokenAmount = tokenIds.length *
            Constants.FLOOR_TOKEN_AMOUNT *
            ((10_000 + commonPoolCommission) / 10_000);

        address fragmentToken = fragmentTokenOf(collection);

        /// approve all
        approveAllERC721(collection, address(_scattering));
        approveAllERC20(fragmentToken, uniswapRouter, fragmentTokenAmount);

        /// transfer tokens into this
        ERC721Transfer.safeBatchTransferFrom(collection, msg.sender, address(this), tokenIds);

        /// fragment
        _scattering.fragmentNFTs(collection, tokenIds, msg.sender);
        IERC20(fragmentToken).transferFrom(msg.sender, address(this), fragmentTokenAmount);

        swapOut = ISwapRouter(uniswapRouter).exactInput(swapParam);

        if (unwrapWETH) {
            unwrapWETH9(swapOut, msg.sender);
        }
    }

    function buyAndClaimExpired(
        address collection,
        uint256[] calldata tokenIds,
        uint256 claimCnt,
        address swapTokenIn,
        ISwapRouter.ExactOutputParams memory swapParam
    ) external payable returns (uint256 tokenCost) {
        _scattering.tidyExpiredNFTs(collection, tokenIds);
        return buyAndClaimVault(collection, claimCnt, swapTokenIn, swapParam);
    }

    function buyAndClaimVault(
        address collection,
        uint256 claimCnt,
        address swapTokenIn,
        ISwapRouter.ExactOutputParams memory swapParam
    ) public payable nonReentrant returns (uint256 tokenCost) {
        uint256 fragmentTokenAmount = claimCnt * Constants.FLOOR_TOKEN_AMOUNT;

        address fragmentToken = fragmentTokenOf(collection);

        approveAllERC20(fragmentToken, address(_scattering), fragmentTokenAmount);

        tokenCost = swapExactOutput(msg.sender, swapTokenIn, swapParam);

        _scattering.claimRandomNFT(collection, claimCnt, /* 0, */ msg.sender);
    }

    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable {
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        if (balanceWETH9 < amountMinimum) {
            revert InsufficientWETH9();
        }

        if (balanceWETH9 > 0) {
            IWETH9(WETH9).withdraw(balanceWETH9);
            CurrencyTransfer.safeTransfer(CurrencyTransfer.NATIVE, recipient, balanceWETH9);
        }
    }

    function swapExactOutput(
        address payer,
        address tokenIn,
        ISwapRouter.ExactOutputParams memory param
    ) internal returns (uint256 amountIn) {
        if (tokenIn == WETH9 && address(this).balance >= param.amountInMaximum) {
            amountIn = ISwapRouter(uniswapRouter).exactOutput{value: param.amountInMaximum}(param);
            IPeripheryPayments(uniswapRouter).refundETH();
            if (address(this).balance > 0) {
                CurrencyTransfer.safeTransfer(CurrencyTransfer.NATIVE, payer, address(this).balance);
            }
        } else {
            approveAllERC20(tokenIn, uniswapRouter, param.amountInMaximum);
            CurrencyTransfer.safeTransferFrom(tokenIn, payer, address(this), param.amountInMaximum);
            amountIn = ISwapRouter(uniswapRouter).exactOutput(param);

            if (param.amountInMaximum > amountIn) {
                CurrencyTransfer.safeTransfer(tokenIn, payer, param.amountInMaximum - amountIn);
            }
        }
    }

    function approveAllERC20(address token, address spender, uint256 desireAmount) private {
        if (desireAmount == 0) {
            return;
        }
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < desireAmount) {
            IERC20(token).approve(spender, type(uint256).max);
        }
    }

    function approveAllERC721(address collection, address spender) private {
        bool approved = IERC721(collection).isApprovedForAll(address(this), spender);
        if (!approved) {
            IERC721(collection).setApprovalForAll(spender, true);
        }
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function extMulticall(CallData[] calldata calls) external override(Multicall) onlyOwner returns (bytes[] memory) {
        return multicall2(calls);
    }

    receive() external payable {
        if (msg.sender != uniswapRouter && msg.sender != WETH9) revert NotRouterOrWETH9();
    }
}
