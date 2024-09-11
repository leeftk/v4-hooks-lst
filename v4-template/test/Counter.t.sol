// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {JITLiquidity} from "../src/JITLiquidity.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";


contract CounterTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;


    PoolId poolId;

    uint256 tokenId;
    PositionConfig config;

    JITLiquidity hook;
    PoolKey poolKey;

    address avsAddress;

    MockERC20 token0;
    MockERC20 token1;


    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
   

        deployAndApprovePosm(manager);
        address avs = address(0x1);
        
        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)
        );
        bytes memory constructorArgs = abi.encode(manager, address(avs), address(posm)); //Add all the necessary constructor arguments from the hook
        deployCodeTo("JITLiquidity.sol:JITLiquidity", constructorArgs, flags);
        hook = JITLiquidity(flags);
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(hook)));
        
    }

    function testCounterHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        assertEq(hook.beforeSwapCount(poolId), 0);
        assertEq(hook.afterSwapCount(poolId), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        posm.decreaseLiquidity(
            tokenId,
            config,
            liquidityToRemove,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);
    }
}
