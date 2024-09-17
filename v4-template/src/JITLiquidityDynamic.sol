// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {EasyPosm} from "./EasyPosm.sol";
import {IPool} from "v4-core/src/interfaces/IPool.sol";

contract JITLiquidityDynamic is ImmutableState {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;

    IPositionManager public immutable positionManager;

    struct UserPosition {
        uint256 newTokenId;
        uint256 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 feesClaimed;
    }

    mapping(address => mapping(PoolId => UserPosition)) public userPositions;
    mapping(PoolId => uint256) public totalLiquidity;

    uint256 public constant BASE_LIQUIDITY = 1000;
    uint256 public constant MAX_LIQUIDITY = 1000000;
    uint256 public minProfitThreshold = 0.0001 ether;
    int24 public tickRange = 10;

    bool private locked;

    event LiquidityAdded(address user, PoolId poolId, uint256 amount, int24 tickLower, int24 tickUpper);
    event LiquidityRemoved(address user, PoolId poolId, uint256 amount, uint256 feesCollected);
    event JITLiquidityProvided(PoolId poolId, uint256 amount);

    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor(IPoolManager _poolManager, IPositionManager _positionManager) ImmutableState(_poolManager) {
        positionManager = _positionManager;
        poolManager = _poolManager;
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
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

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (uint160 sqrtPriceX96,,,,,,) = poolManager.getSlot0(key.toId());
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified) 
            : uint256(params.amountSpecified);

        uint256 liquidityToAdd = calculateDynamicLiquidity(swapAmount, key.toId());

        if (isProfitable(liquidityToAdd, key)) {
            int24 tickLower = currentTick - tickRange;
            int24 tickUpper = currentTick + tickRange;

            PositionConfig memory config = PositionConfig({
                poolKey: key,
                tickLower: tickLower,
                tickUpper: tickUpper
            });

            (uint256 newTokenId, BalanceDelta delta) = positionManager.mint(
                config,
                liquidityToAdd,
                type(uint256).max,
                type(uint256).max,
                address(this),
                block.timestamp + 1 hours,
                ""
            );

            handleBalanceDelta(delta, key);
            totalLiquidity[key.toId()] += liquidityToAdd;

            emit JITLiquidityProvided(key.toId(), liquidityToAdd);
        }

        return (Hooks.BEFORE_SWAP_SELECTOR, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        uint256 liquidityToRemove = totalLiquidity[key.toId()];

        if (liquidityToRemove > 0) {
            (uint160 sqrtPriceX96,,,,,,) = poolManager.getSlot0(key.toId());
            int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            PositionConfig memory config = PositionConfig({
                poolKey: key,
                tickLower: currentTick - tickRange,
                tickUpper: currentTick + tickRange
            });

            BalanceDelta delta = positionManager.decreaseLiquidity(
                0, // newTokenId is not used in this context
                config,
                liquidityToRemove,
                0,
                0,
                address(this),
                block.timestamp + 1 hours,
                ""
            );

            handleBalanceDelta(delta, key);
            totalLiquidity[key.toId()] = 0;
        }

        return (Hooks.AFTER_SWAP_SELECTOR, 0);
    }

    function addLiquidity(PoolKey calldata key, uint256 amount) external nonReentrant {
        (uint160 sqrtPriceX96,,,,,,) = poolManager.getSlot0(key.toId());
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        int24 tickLower = currentTick - tickRange;
        int24 tickUpper = currentTick + tickRange;

        PositionConfig memory config = PositionConfig({
            poolKey: key,
            tickLower: tickLower,
            tickUpper: tickUpper
        });

        UserPosition storage position = userPositions[msg.sender][key.toId()];

        if (position.newTokenId == 0) {
            (uint256 newTokenId, BalanceDelta delta) = positionManager.mint(
                config,
                amount,
                type(uint256).max,
                type(uint256).max,
                msg.sender,
                block.timestamp + 1 hours,
                ""
            );
            position.newTokenId = newTokenId;
            handleBalanceDelta(delta, key);
        } else {
            BalanceDelta delta = positionManager.increaseLiquidity(
                position.newTokenId,
                config,
                amount,
                type(uint256).max,
                type(uint256).max,
                block.timestamp + 1 hours,
                ""
            );
            handleBalanceDelta(delta, key);
        }

        position.liquidity += amount;
        position.tickLower = tickLower;
        position.tickUpper = tickUpper;

        emit LiquidityAdded(msg.sender, key.toId(), amount, tickLower, tickUpper);
    }

    function removeLiquidity(PoolKey calldata key) external nonReentrant {
        UserPosition storage position = userPositions[msg.sender][key.toId()];
        require(position.liquidity > 0, "No liquidity to remove");

        PositionConfig memory config = PositionConfig({
            poolKey: key,
            tickLower: position.tickLower,
            tickUpper: position.tickUpper
        });

        BalanceDelta delta = positionManager.decreaseLiquidity(
            position.newTokenId,
            config,
            position.liquidity,
            0,
            0,
            msg.sender,
            block.timestamp + 1 hours,
            ""
        );

        uint256 feesCollected = uint256(uint128(delta.amount0())) + uint256(uint128(delta.amount1()));
        handleBalanceDelta(delta, key);

        position.feesClaimed += feesCollected;
        uint256 removedLiquidity = position.liquidity;
        position.liquidity = 0;

        emit LiquidityRemoved(msg.sender, key.toId(), removedLiquidity, feesCollected);
    }

    function calculateDynamicLiquidity(uint256 swapAmount, PoolId poolId) public view returns (uint256) {
        uint256 poolLiquidity = totalLiquidity[poolId];
        uint256 calculatedLiquidity = BASE_LIQUIDITY + (swapAmount * 2 / (poolLiquidity + 1));

        return calculatedLiquidity > MAX_LIQUIDITY ? MAX_LIQUIDITY : calculatedLiquidity;
    }

    function isProfitable(uint256 liquidityToAdd, PoolKey calldata key) public view returns (bool) {
        uint24 swapFee = key.fee;
        uint256 estimatedFee = liquidityToAdd * swapFee / 1e6;
        uint256 gasCost = tx.gasprice * 300000; // Estimated gas usage

        return estimatedFee > gasCost + minProfitThreshold;
    }

    function handleBalanceDelta(BalanceDelta delta, PoolKey calldata key) internal {
        if (delta.amount0() > 0) {
            poolManager.take(key.currency0, address(this), uint128(delta.amount0()));
        } else if (delta.amount0() < 0) {
            key.currency0.transfer(address(poolManager), uint128(-delta.amount0()));
        }

        if (delta.amount1() > 0) {
            poolManager.take(key.currency1, address(this), uint128(delta.amount1()));
        } else if (delta.amount1() < 0) {
            key.currency1.transfer(address(poolManager), uint128(-delta.amount1()));
        }
    }

    // Add any additional helper functions or governance functions here
}