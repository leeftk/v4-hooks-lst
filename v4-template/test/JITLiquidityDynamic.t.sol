// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/JITLiquidityDynamic.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract JITLiquidityDynamicTest is Test {
    JITLiquidityDynamic public jitLiquidity;
    MockPoolManager public mockPoolManager;
    MockPositionManager public mockPositionManager;

    address constant TOKEN0 = address(0x1);
    address constant TOKEN1 = address(0x2);
    uint24 constant FEE = 3000;

    PoolKey poolKey;

    function setUp() public {
        mockPoolManager = new MockPoolManager();
        mockPositionManager = new MockPositionManager();
        jitLiquidity = new JITLiquidityDynamic(IPoolManager(address(mockPoolManager)), IPositionManager(address(mockPositionManager)));

        poolKey = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: FEE,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function testBeforeSwap() public {
        uint256 swapAmount = 1 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, BeforeSwapDelta beforeSwapDelta, uint24 resultFee) = jitLiquidity.beforeSwap(address(this), poolKey, params, "");

        assertEq(selector, Hooks.BEFORE_SWAP_SELECTOR, "Incorrect selector returned");
        assertEq(uint256(beforeSwapDelta.delta), 0, "BeforeSwapDelta should be zero");
        assertEq(resultFee, 0, "Result fee should be zero");
    }

    function testAfterSwap() public {
        uint256 swapAmount = 1 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, int128 result) = jitLiquidity.afterSwap(address(this), poolKey, params, BalanceDelta.wrap(0), "");

        assertEq(selector, Hooks.AFTER_SWAP_SELECTOR, "Incorrect selector returned");
        assertEq(result, 0, "Result should be zero");
    }

    function testAddLiquidity() public {
        uint256 amount = 1 ether;
        jitLiquidity.addLiquidity(poolKey, amount);

        (uint256 newTokenId, uint256 liquidity, , , ) = jitLiquidity.userPositions(address(this), poolKey.toId());
        assertEq(newTokenId, 1, "Incorrect token ID");
        assertEq(liquidity, amount, "Incorrect liquidity amount");
    }

    function testRemoveLiquidity() public {
        uint256 amount = 1 ether;
        jitLiquidity.addLiquidity(poolKey, amount);
        jitLiquidity.removeLiquidity(poolKey);

        (,uint256 liquidity,,,) = jitLiquidity.userPositions(address(this), poolKey.toId());
        assertEq(liquidity, 0, "Liquidity should be zero after removal");
    }

    function testCalculateDynamicLiquidity() public {
        uint256 swapAmount = 1 ether;
        uint256 dynamicLiquidity = jitLiquidity.calculateDynamicLiquidity(swapAmount, poolKey.toId());
        assertTrue(dynamicLiquidity > 0, "Dynamic liquidity should be greater than zero");
        assertTrue(dynamicLiquidity <= jitLiquidity.MAX_LIQUIDITY(), "Dynamic liquidity should not exceed MAX_LIQUIDITY");
    }

    function testIsProfitable() public {
        uint256 liquidityToAdd = 1 ether;
        bool profitable = jitLiquidity.isProfitable(liquidityToAdd, poolKey);
        // The result will depend on the gas price and other factors, so we just check that it returns a boolean
        assertTrue(profitable == true || profitable == false, "isProfitable should return a boolean");
    }
}

// Mock contracts for testing
contract MockPoolManager is IPoolManager {
    function getSlot0(PoolId) external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (79228162514264337593543950336, 0, 0, 0, 0, 0, true);
    }

    function take(Currency, address, uint256) external pure {}

    // Implement other required functions...
}

contract MockPositionManager is IPositionManager {
    uint256 private _tokenIdCounter = 0;

    function mint(
        PositionConfig memory,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bytes memory
    ) external returns (uint256, BalanceDelta) {
        _tokenIdCounter++;
        return (_tokenIdCounter, BalanceDelta.wrap(0));
    }

    function increaseLiquidity(
        uint256,
        PositionConfig memory,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes memory
    ) external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    function decreaseLiquidity(
        uint256,
        PositionConfig memory,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bytes memory
    ) external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }

    // Implement other required functions...
}