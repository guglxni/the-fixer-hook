// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixerRegistryStorage} from "../storage/FixerRegistryStorage.sol";

/// @title AgentTierConstants
/// @notice Constants for agent tier configuration
/// @dev FINALIZED values from Market Sentiment Analysis
library AgentTierConstants {
    // ========================================================================
    // STAKE AMOUNTS
    // ========================================================================

    uint256 constant UNVERIFIED_STAKE = 0;
    uint256 constant STARTER_STAKE = 100e18;          // 100 FIX
    uint256 constant PROFESSIONAL_STAKE = 1_000e18;   // 1,000 FIX
    uint256 constant ENTERPRISE_STAKE = 10_000e18;    // 10,000 FIX
    uint256 constant AUDITED_STAKE = 10_000e18;       // 10,000 FIX + audit

    // ========================================================================
    // REWARD MULTIPLIERS (basis points, 10000 = 1.0x)
    // ========================================================================

    uint16 constant UNVERIFIED_MULTIPLIER = 0;        // No rewards
    uint16 constant STARTER_MULTIPLIER = 10000;       // 1.0x
    uint16 constant PROFESSIONAL_MULTIPLIER = 12500;  // 1.25x
    uint16 constant ENTERPRISE_MULTIPLIER = 15000;    // 1.5x
    uint16 constant AUDITED_MULTIPLIER = 20000;       // 2.0x

    // ========================================================================
    // SLASHING RATES (basis points)
    // ========================================================================

    uint16 constant STARTER_SLASHING = 1000;          // 10% = 10 FIX
    uint16 constant PROFESSIONAL_SLASHING = 1500;     // 15% = 150 FIX
    uint16 constant ENTERPRISE_SLASHING = 2000;       // 20% = 2,000 FIX
    uint16 constant AUDITED_SLASHING = 500;           // 5% = 500 FIX (trusted)

    // ========================================================================
    // CHAIN ACCESS
    // ========================================================================

    uint8 constant UNVERIFIED_MAX_CHAINS = 0;
    uint8 constant STARTER_MAX_CHAINS = 1;
    uint8 constant PROFESSIONAL_MAX_CHAINS = 5;
    uint8 constant ENTERPRISE_MAX_CHAINS = 20;
    uint8 constant AUDITED_MAX_CHAINS = 255;          // Unlimited

    // ========================================================================
    // UNSTAKE COOLDOWN
    // ========================================================================

    uint256 constant UNSTAKE_COOLDOWN = 7 days;
}

/// @title TeamLimits
/// @notice Constants for team size and bonus configuration
/// @dev FINALIZED: 5 (Bronze) → 50 (Platinum)
library TeamLimits {
    // ========================================================================
    // MAX MEMBERS BY TIER
    // ========================================================================

    uint8 constant BRONZE_MAX = 5;
    uint8 constant SILVER_MAX = 10;
    uint8 constant GOLD_MAX = 25;
    uint8 constant PLATINUM_MAX = 50;

    // ========================================================================
    // TEAM BONUS POOL (basis points)
    // ========================================================================

    uint16 constant BRONZE_BONUS = 250;     // 2.5%
    uint16 constant SILVER_BONUS = 500;     // 5%
    uint16 constant GOLD_BONUS = 750;       // 7.5%
    uint16 constant PLATINUM_BONUS = 1000;  // 10%

    // ========================================================================
    // LEADER SHARE OF BONUS (basis points)
    // ========================================================================

    uint16 constant BRONZE_LEADER = 5000;   // 50%
    uint16 constant SILVER_LEADER = 4500;   // 45%
    uint16 constant GOLD_LEADER = 4250;     // 42.5%
    uint16 constant PLATINUM_LEADER = 4000; // 40%

    // ========================================================================
    // TEAM LIFECYCLE
    // ========================================================================

    uint256 constant LEAVE_NOTICE_PERIOD = 7 days;
    uint256 constant INACTIVITY_DISSOLVE = 90 days;
}

/// @title ProtocolFeeConstants
/// @notice Constants for protocol fee configuration
/// @dev FINALIZED: 5% at launch, DAO-governed (max 10%)
library ProtocolFeeConstants {
    uint64 constant DEFAULT_FEE_BPS = 500;     // 5%
    uint64 constant MAX_FEE_BPS = 1000;        // 10% hard cap

    // Fee distribution (basis points of total fee)
    uint16 constant TREASURY_SHARE = 5000;     // 50%
    uint16 constant BUYBACK_SHARE = 3000;      // 30%
    uint16 constant STAKER_SHARE = 2000;       // 20%
}
