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

contract JITLiquidity is BaseHook {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;

    // State variables
    mapping(PoolId => uint256) public beforeAddLiquidityCount;
    mapping(PoolId => uint256) public beforeRemoveLiquidityCount;
    mapping(PoolId => uint256) public beforeSwapCount;
    mapping(PoolId => uint256) public afterSwapCount;
    address public avsAddress;
    IPositionManager public positionManager;

    // Events
    event LiquidityAdded(PoolId indexed poolId, uint256 tokenId, uint256 amount);
    event LiquidityRemoved(PoolId indexed poolId, uint256 tokenId, uint256 amount);

    constructor(IPoolManager _poolManager, address _avsAddress, IPositionManager _positionManager) BaseHook(_poolManager) {
        avsAddress = _avsAddress;
        positionManager = _positionManager;
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

    function beforeAddLiquidity(address, PoolKey calldata key, bytes calldata)
        external

        returns (bytes4)
    {
        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(address, PoolKey calldata key, bytes calldata)
        external
    
        returns (bytes4)
    {
        beforeRemoveLiquidityCount[key.toId()]++;
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount[key.toId()]++;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        afterSwapCount[key.toId()]++;
        return (BaseHook.afterSwap.selector, 0);
    }

    // Function to add liquidity (only callable by AVS)
    function addLiquidity(
        uint256 tokenId,
        PositionConfig calldata config,
        uint256 amount,
        uint256 maxSlippage0,
        uint256 maxSlippage1
    ) external {
        //require(msg.sender == avsAddress, "Only AVS can add liquidity");
        
        // positionManager.increaseLiquidity(
        //     tokenId,
        //     config,
        //     amount,
        //     maxSlippage0,
        //     maxSlippage1,
        //     address(this),
        //     block.timestamp,
        //     abi.encode(0) // ZERO_BYTES
        // );

        emit LiquidityAdded(config.poolKey.toId(), tokenId, amount);
    }

    // Function to remove liquidity (only callable by AVS)
    function removeLiquidity(
        uint256 tokenId,
        PositionConfig calldata config,
        uint256 liquidityToRemove,
        uint256 maxSlippage0,
        uint256 maxSlippage1
    ) external {
        //require(msg.sender == avsAddress, "Only AVS can remove liquidity");
        
        positionManager.decreaseLiquidity(
            tokenId,
            config,
            liquidityToRemove,
            maxSlippage0,
            maxSlippage1,
            address(this),
            block.timestamp,
            abi.encode(0) // ZERO_BYTES
        );

        emit LiquidityRemoved(config.poolKey.toId(), tokenId, liquidityToRemove);
    }
}
