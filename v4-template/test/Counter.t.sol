// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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
import {MockERC20} from "./utils/MockERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {LiquidityOperations} from "v4-periphery/test/shared/LiquidityOperations.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

contract CounterTest is Test, Fixtures, LiquidityOperations {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    PoolId poolId;
    LiquidityOperations liquidityOperations;

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
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            )
        );
        bytes memory constructorArgs = abi.encode(manager, posm); //Add all the necessary constructor arguments from the hook
        deployCodeTo("JITLiquidity.sol:JITLiquidity", constructorArgs, flags);
        hook = JITLiquidity(flags);
        //transfer currency1 to the hook
        currency0.transfer(address(hook), 1000000000000 ether);
        currency1.transfer(address(hook), 1000000000000 ether);

        // Create the pool
        key = PoolKey(currency0, currency1, 300000, 60, IHooks(address(hook)));
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
        // full-range liquidity
        config = PositionConfig({
            poolKey: key,
            tickLower: TickMath.minUsableTick(key.tickSpacing),
            tickUpper: TickMath.maxUsableTick(key.tickSpacing)
        });

        //deal ether to the hook
        deal(address(hook), 1000000 ether);
    }

    function test_AddLiquidity_BeforeSwap() public {
        //get amount for liquidity before swao
        uint256 liquidityToMint = 100e18;
        uint256 tokenId = posm.nextTokenId();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(config.tickLower),
            TickMath.getSqrtPriceAtTick(config.tickUpper),
            uint128(liquidityToMint)
        );

        uint256 positionLiquidity = posm.getPositionLiquidity(tokenId, config);
        console.log("beforeSwap Liquidity amount psom", positionLiquidity);

        uint256 hookTokenId = posm.nextTokenId();
        positionLiquidity = posm.getPositionLiquidity(hookTokenId, config);
        

        
        uint256 newLiquidity = 10e18;

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        //bytes memory calls = getIncreaseEncoded(tokenId, config, newLiquidity, ZERO_BYTES);
        //negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);
        assertEq(int256(swapDelta.amount0()), amountSpecified);


        
    

        positionLiquidity = posm.getPositionLiquidity(hookTokenId - 1, config);

    }

    function testLiquidityHooks() public {
        (uint256 tokenId,) = posm.mint(
            config,
            100e18,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp + 1,
            ZERO_BYTES
        );
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
        console.log("liquidity removed");
    }

  
}
