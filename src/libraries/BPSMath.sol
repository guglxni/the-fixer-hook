// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title BPSMath
/// @author Aaryan Guglani
/// @notice Centralized basis-point arithmetic using audited mulDiv
/// @dev All BPS operations in the protocol MUST use this library.
///      Uses Solady's FixedPointMathLib.mulDiv for overflow-safe computation.
///
/// BPS Reference:
///   1 bps  = 0.01% = 1/10000
///   100 bps = 1%
///   10000 bps = 100%
///   12500 bps = 125% (1.25x multiplier)
library BPSMath {
    /// @notice Maximum basis points (100%)
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Apply a basis point rate: amount × bps / 10000
    /// @param amount The base amount
    /// @param bps The basis point rate to apply
    /// @return result The computed value (rounded down)
    function applyBPS(uint256 amount, uint256 bps) internal pure returns (uint256 result) {
        result = FixedPointMathLib.mulDiv(amount, bps, BPS_DENOMINATOR);
    }

    /// @notice Deduct a basis point fee, returning (net, fee)
    /// @param amount The gross amount
    /// @param feeBps The fee in basis points
    /// @return net The amount after fee deduction
    /// @return fee The fee amount
    function deductFee(uint256 amount, uint256 feeBps) internal pure returns (uint256 net, uint256 fee) {
        fee = applyBPS(amount, feeBps);
        net = amount - fee;
    }

    /// @notice Apply a multiplier expressed in BPS (e.g., 12500 = 1.25x)
    /// @param amount The base amount
    /// @param multiplierBps The multiplier in basis points (10000 = 1.0x)
    /// @return result The scaled value
    function applyMultiplier(uint256 amount, uint256 multiplierBps) internal pure returns (uint256 result) {
        result = FixedPointMathLib.mulDiv(amount, multiplierBps, BPS_DENOMINATOR);
    }
}
