// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC8004IdentityRegistry} from "../interfaces/IERC8004IdentityRegistry.sol";
import {IERC8004ReputationRegistry} from "../interfaces/IERC8004ReputationRegistry.sol";
import {IERC8004ValidationRegistry} from "../interfaces/IERC8004ValidationRegistry.sol";
import {ERC8004Constants} from "../types/AgentTypes.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title FixerLib
/// @author Aaryan Guglani
/// @notice External library for computation-heavy operations
/// @dev Public functions are deployed as a separate contract and called via DELEGATECALL,
///      reducing FixerRegistryUpgradeable below the EIP-170 contract size limit (24,576 bytes).
///      Foundry auto-deploys and links this library during `forge script` broadcasts.
library FixerLib {
    // ========================================================================
    // ERRORS (mirrored from IAgentRegistry — same selectors)
    // ========================================================================

    error InvalidAgentIdOwnership();
    error AgentWalletMismatch();
    error MinimumValidationScoreNotMet();
    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error InvalidSignature();

    // ========================================================================
    // ERC-8004 AGENT VALIDATION
    // ========================================================================

    /// @notice Validate ERC-8004 agent ownership and optional validation score
    /// @dev Performs external calls to identity and validation registries.
    ///      Reverts with matching IAgentRegistry error selectors on failure.
    /// @param identityRegistry ERC-8004 Identity Registry address
    /// @param validationRegistry ERC-8004 Validation Registry address (address(0) to skip)
    /// @param agentId The ERC-8004 agent NFT ID
    /// @param caller The address claiming ownership
    function validateAgent(
        address identityRegistry,
        address validationRegistry,
        uint256 agentId,
        address caller
    ) public view {
        IERC8004IdentityRegistry identity = IERC8004IdentityRegistry(identityRegistry);

        // Verify caller owns the ERC-8004 Identity NFT
        if (identity.ownerOf(agentId) != caller) revert InvalidAgentIdOwnership();

        // Verify caller is the registered agentWallet
        if (identity.getAgentWallet(agentId) != caller) revert AgentWalletMismatch();

        // Optional: Check validation score if registry is configured
        if (validationRegistry != address(0) && ERC8004Constants.MIN_VALIDATION_SCORE > 0) {
            IERC8004ValidationRegistry validation = IERC8004ValidationRegistry(validationRegistry);
            (, uint8 avgScore) = validation.getSummary(agentId, new address[](0), bytes32(0));
            if (avgScore < ERC8004Constants.MIN_VALIDATION_SCORE) revert MinimumValidationScoreNotMet();
        }
    }

    // ========================================================================
    // ERC-8004 REPUTATION
    // ========================================================================

    /// @notice Fetch reputation from ERC-8004 registry and compute bonus
    /// @dev Wrapped in try/catch — returns success=false on external call failure.
    ///      Never reverts, ensuring core referral flow is never blocked.
    /// @param reputationRegistry ERC-8004 Reputation Registry address
    /// @param agentId The ERC-8004 agent NFT ID
    /// @return success Whether the reputation fetch succeeded
    /// @return score The raw reputation score (signed fixed-point)
    /// @return decimals The number of decimals in the score
    /// @return bonusBps The computed reputation-derived bonus in basis points
    function fetchReputation(
        address reputationRegistry,
        uint256 agentId
    ) public view returns (bool success, int128 score, uint8 decimals, uint16 bonusBps) {
        IERC8004ReputationRegistry reputation = IERC8004ReputationRegistry(reputationRegistry);

        try reputation.getSummary(
            agentId,
            new address[](0),
            ERC8004Constants.TAG_REFERRAL,
            bytes32(0)
        ) returns (uint256, int128 summaryValue, uint8 repDecimals) {
            return (true, summaryValue, repDecimals, computeReputationBonus(summaryValue, repDecimals));
        } catch {
            return (false, 0, 0, 0);
        }
    }

    /// @notice Submit referral performance feedback to ERC-8004 reputation registry
    /// @dev Wrapped in try/catch — returns false on failure. Never blocks operations.
    /// @param reputationRegistry ERC-8004 Reputation Registry address
    /// @param agentId The ERC-8004 agent NFT ID
    /// @param score The feedback score to submit
    /// @return success Whether the feedback submission succeeded
    function sendFeedback(
        address reputationRegistry,
        uint256 agentId,
        int128 score
    ) public returns (bool success) {
        IERC8004ReputationRegistry reputation = IERC8004ReputationRegistry(reputationRegistry);

        try reputation.giveFeedback(
            agentId,
            score,
            0, // valueDecimals: integer score
            ERC8004Constants.TAG_REFERRAL,
            ERC8004Constants.TAG_VOLUME,
            bytes32(0), // endpoint
            "", // feedbackURI
            bytes32(0) // feedbackHash
        ) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Compute reputation-derived bonus from ERC-8004 reputation score
    /// @dev Normalizes signed fixed-point score to integer 0-100, then maps to tiered BPS:
    ///      81-100 → BONUS_ELITE (5000 BPS, 50%)
    ///      61-80  → BONUS_HIGH  (3000 BPS, 30%)
    ///      31-60  → BONUS_MEDIUM (1500 BPS, 15%)
    ///      1-30   → BONUS_LOW   (500 BPS, 5%)
    ///      ≤0     → BONUS_NONE  (0 BPS)
    /// @param score The raw reputation score (signed fixed-point)
    /// @param scoreDecimals The number of decimals in the score
    /// @return bonusBps The reputation-derived bonus in basis points
    function computeReputationBonus(
        int128 score,
        uint8 scoreDecimals
    ) public pure returns (uint16 bonusBps) {
        // Negative or zero reputation = no bonus
        if (score <= 0) return ERC8004Constants.BONUS_NONE;

        // Normalize to integer 0-100 scale
        int128 normalized;
        if (scoreDecimals == 0) {
            normalized = score;
        } else {
            // Divide by 10^decimals to get integer part
            int128 divisor = int128(int256(10 ** uint256(scoreDecimals)));
            normalized = score / divisor;
        }

        // Clamp to 0-100
        if (normalized > 100) normalized = 100;
        if (normalized <= 0) return ERC8004Constants.BONUS_NONE;

        // Map to tiered bonus
        if (normalized >= ERC8004Constants.REPUTATION_ELITE_MIN) {
            return ERC8004Constants.BONUS_ELITE;     // 81-100: 50%
        } else if (normalized >= ERC8004Constants.REPUTATION_HIGH_MIN) {
            return ERC8004Constants.BONUS_HIGH;      // 61-80:  30%
        } else if (normalized >= ERC8004Constants.REPUTATION_MEDIUM_MIN) {
            return ERC8004Constants.BONUS_MEDIUM;    // 31-60:  15%
        } else {
            return ERC8004Constants.BONUS_LOW;       // 1-30:    5%
        }
    }

    // ========================================================================
    // EIP-3009 AUTH VALIDATION
    // ========================================================================

    /// @notice Validate EIP-3009 transferWithAuthorization parameters and signature
    /// @dev Verifies timing, computes EIP-712 digest, and recovers signer via ECDSA.
    ///      Moves the ECDSA.recover bytecode out of the main contract.
    function validateAuth(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s_,
        bytes32 domainSeparator,
        bytes32 typehash
    ) public view returns (bytes32 authKey) {
        if (block.timestamp < validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp > validBefore) revert AuthorizationExpired();

        bytes32 structHash = keccak256(
            abi.encode(typehash, from, to, value, validAfter, validBefore, nonce)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ECDSA.recover(digest, v, r, s_);
        if (signer != from) revert InvalidSignature();

        authKey = keccak256(abi.encodePacked(from, nonce));
    }
}
