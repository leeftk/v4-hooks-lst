// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {EasyPosm} from "./EasyPosm.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "forge-std/console.sol";
import {LiquidityOperations} from "v4-periphery/test/shared/LiquidityOperations.sol";
import {LPFeeLibrary} from "v4-periphery/lib/v4-core/src/libraries/LPFeeLibrary.sol";

contract JITLiquidity is BaseHook, LiquidityOperations {
    using PoolIdLibrary for PoolKey;
    using EasyPosm for IPositionManager;
    IPositionManager public posm;
    IPoolManager public manager;
    PositionConfig config;
    IAllowanceTransfer public permit2;

    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    bytes constant ZERO_BYTES = new bytes(0);

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    constructor(IPoolManager _poolManager, IPositionManager _posm) BaseHook(_poolManager) {
        posm = _posm;
        manager = _poolManager;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        console.log("amount in manager before swap", IERC20(Currency.unwrap(key.currency0)).balanceOf(address(manager)));
        console.log("amount in manager before swap", IERC20(Currency.unwrap(key.currency1)).balanceOf(address(manager)));
        uint256 liquidity = 100e18;
        uint256 slippage = 100e18;
        uint256 deadline = block.timestamp + 1;
        int256 liquidityDelta = 10000 ether;
        int24 tickSpacing = 60;
        //@note inistliaze pool with fee
        //manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
        (BalanceDelta delta,) = manager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), liquidityDelta, 0
            ),
            ZERO_BYTES
        );
        

        // Handle delta.amount0()
        if (delta.amount0() < 0) {
            // Negative Value => Money leaving contract's wallet
            // Settle with PoolManager
            _settle(key.currency0, uint128(-delta.amount0()));
        } else if (delta.amount0() > 0) {
            // Positive Value => Money coming into contract's wallet
            // Take from PoolManager
            _take(key.currency0, uint128(delta.amount0()));
        }

        // Handle delta.amount1()
        if (delta.amount1() < 0) {
            // Negative Value => Money leaving contract's wallet
            // Settle with PoolManager
            _settle(key.currency1, uint128(-delta.amount1()));
        } else if (delta.amount1() > 0) {
            // Positive Value => Money coming into contract's wallet
            // Take from PoolManager
            _take(key.currency1, uint128(delta.amount1()));
        }

      

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        uint256 liquidity = 100e18;
        uint256 slippage = 100e18;
        uint256 deadline = block.timestamp + 1;
        console.log("amount currecy0 in manager", IERC20(Currency.unwrap(key.currency0)).balanceOf(address(manager)));
        console.log("amount currecy1 in manager", IERC20(Currency.unwrap(key.currency1)).balanceOf(address(manager)));

        int256 liquidityDelta = -9999.000009 ether;
        int24 tickSpacing = 60;
        (BalanceDelta delta,) = manager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), liquidityDelta, 0
            ),
            ZERO_BYTES
        );

       
        // Handle delta.amount0()
        if (delta.amount0() < 0) {
            // Negative Value => Money leaving contract's wallet
            // Settle with PoolManager
            _settle(key.currency0, uint128(-delta.amount0()));
        } else if (delta.amount0() > 0) {
            // Positive Value => Money coming into contract's wallet
            // Take from PoolManager
            _take(key.currency0, uint128(delta.amount0()));
        }

        // Handle delta.amount1()
        if (delta.amount1() < 0) {
            // Negative Value => Money leaving contract's wallet
            // Settle with PoolManager
            _settle(key.currency1, uint128(-delta.amount1()));
        } else if (delta.amount1() > 0) {
            // Positive Value => Money coming into contract's wallet
            // Take from PoolManager
            _take(key.currency1, uint128(delta.amount1()));
        }
        return (BaseHook.afterSwap.selector, 0);
    }


    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;
        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeRemoveLiquidityCount[key.toId()]++;
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function approvePosmCurrency(Currency currency) internal {
        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        // 2. Then, the caller must approve POSM as a spender of permit2. TODO: This could also be a signature.
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }

    function _settle(Currency currency, uint128 amount) internal {
        // Transfer tokens to PM and let it know
        manager.sync(currency);
   
        currency.transfer(address(manager), amount);
        manager.settle();
    }

    function _take(Currency currency, uint128 amount) internal returns (uint256) {
        // Record balance before taking tokens
        uint256 balanceBefore = IERC20(Currency.unwrap(currency)).balanceOf(address(this));

        // Take tokens out of PM to our hook contract
        manager.take(currency, address(this), amount);

        // Record balance after taking tokens
        uint256 balanceAfter = IERC20(Currency.unwrap(currency)).balanceOf(address(this));

        // Calculate the actual amount bought
        uint256 amountBought = balanceAfter - balanceBefore;

        return amountBought;
    }
}
