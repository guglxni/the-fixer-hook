// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixerRegistryStorage} from "../storage/FixerRegistryStorage.sol";

/// @title EmergencyModule
/// @author Aaryan Guglani
/// @notice Circuit breakers and emergency pause for FixerRegistryUpgradeable
/// @dev Abstract module providing:
///      - Independent pause states (referrals, agents, rewards)
///      - Security council fast-path pause
///      - DAO requirement for extended pauses (>7 days)
///      - Hourly circuit breaker on FIX minting
///
/// Decision Applied:
/// > Security council can pause, DAO required for > 7 day resume
abstract contract EmergencyModule {
    using FixerRegistryStorage for *;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Duration after which only DAO governance can resume
    uint256 public constant PAUSE_DAO_THRESHOLD = 7 days;

    /// @notice Default circuit breaker threshold (can be updated)
    uint256 public constant DEFAULT_CIRCUIT_BREAKER = 1_000_000e18; // 1M FIX/hour

    /// @notice Minimum allowed circuit breaker threshold
    /// @dev Prevents owner/council from disabling circuit breaker by setting threshold to max
    uint256 public constant MIN_CIRCUIT_BREAKER = 100_000e18; // 100k FIX/hour minimum

    /// @notice Maximum FIX tokens that can be minted per day (10 million)
    /// @dev Provides a second layer of defense beyond the hourly circuit breaker
    uint256 public constant MAX_DAILY_MINT = 10_000_000e18;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event ReferralsPaused(address indexed by, uint256 timestamp);
    event ReferralsResumed(address indexed by, uint256 timestamp);
    event AgentsPaused(address indexed by, uint256 timestamp);
    event AgentsResumed(address indexed by, uint256 timestamp);
    event RewardsPaused(address indexed by, uint256 timestamp);
    event RewardsResumed(address indexed by, uint256 timestamp);
    event CircuitBreakerTriggered(string reason, uint256 amount);
    event DailyMintCeilingTriggered(uint256 mintedToday);
    event CircuitBreakerThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event SecurityCouncilUpdated(address indexed oldCouncil, address indexed newCouncil);
    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotSecurityCouncil();
    error NotGovernance();
    error NotSecurityCouncilOrGovernance();
    error ReferralSystemPaused();     // Modifier guard: referrals currently paused
    error ReferralsAlreadyPaused();   // Double-pause prevention
    error ReferralsNotPaused();
    error AgentSystemPaused();        // Modifier guard: agents currently paused
    error AgentsAlreadyPaused();      // Double-pause prevention
    error AgentsNotPaused();
    error RewardSystemPaused();       // Modifier guard: rewards currently paused
    error RewardsAlreadyPaused();     // Double-pause prevention
    error RewardsNotPaused();
    error DAOVoteRequiredForResume();
    error ZeroAddress();
    error CircuitBreakerActive();
    error ThresholdBelowMinimum();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /// @notice Ensures referral processing is not paused
    modifier whenNotPausedReferrals() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedReferrals) revert ReferralSystemPaused();
        _;
    }

    /// @notice Ensures agent operations are not paused
    modifier whenNotPausedAgents() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedAgents) revert AgentSystemPaused();
        _;
    }

    /// @notice Ensures reward minting is not paused
    modifier whenNotPausedRewards() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedRewards) revert RewardSystemPaused();
        _;
    }

    /// @notice Restricts function to security council only
    modifier onlySecurityCouncil() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (msg.sender != s.emergency.securityCouncil) revert NotSecurityCouncil();
        _;
    }

    /// @notice Restricts function to governance only
    modifier onlyGovernance() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (msg.sender != s.emergency.governance) revert NotGovernance();
        _;
    }

    /// @notice Restricts function to security council or governance
    modifier onlySecurityCouncilOrGovernance() {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (
            msg.sender != s.emergency.securityCouncil &&
            msg.sender != s.emergency.governance
        ) {
            revert NotSecurityCouncilOrGovernance();
        }
        _;
    }

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    /// @notice Initializes emergency module state
    /// @param securityCouncil_ Address of the security multisig
    /// @param governance_ Address of the DAO governance
    function __EmergencyModule_init(
        address securityCouncil_,
        address governance_
    ) internal {
        if (securityCouncil_ == address(0)) revert ZeroAddress();
        // governance can be zero initially (set later when DAO launched)

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        s.emergency.securityCouncil = securityCouncil_;
        s.emergency.governance = governance_;
        s.emergency.circuitBreakerThreshold = DEFAULT_CIRCUIT_BREAKER;
        s.emergency.hourStartedAt = uint64(block.timestamp);
    }

    // ========================================================================
    // PAUSE FUNCTIONS
    // ========================================================================

    /// @notice Pause referral processing (security council fast-path)
    function pauseReferrals() external onlySecurityCouncil {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedReferrals) revert ReferralsAlreadyPaused();

        s.emergency.pausedReferrals = true;
        s.emergency.pausedReferralsAt = uint64(block.timestamp);
        emit ReferralsPaused(msg.sender, block.timestamp);
    }

    /// @notice Resume referral processing
    /// @dev If paused > 7 days, requires DAO governance vote
    function resumeReferrals() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.emergency.pausedReferrals) revert ReferralsNotPaused();

        _validateResumeAuth(s, s.emergency.pausedReferralsAt);

        s.emergency.pausedReferrals = false;
        s.emergency.pausedReferralsAt = 0;
        emit ReferralsResumed(msg.sender, block.timestamp);
    }

    /// @notice Pause agent operations (security council fast-path)
    function pauseAgents() external onlySecurityCouncil {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedAgents) revert AgentsAlreadyPaused();

        s.emergency.pausedAgents = true;
        s.emergency.pausedAgentsAt = uint64(block.timestamp);
        emit AgentsPaused(msg.sender, block.timestamp);
    }

    /// @notice Resume agent operations
    function resumeAgents() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.emergency.pausedAgents) revert AgentsNotPaused();

        _validateResumeAuth(s, s.emergency.pausedAgentsAt);

        s.emergency.pausedAgents = false;
        s.emergency.pausedAgentsAt = 0;
        emit AgentsResumed(msg.sender, block.timestamp);
    }

    /// @notice Pause reward minting (security council fast-path)
    function pauseRewards() external onlySecurityCouncil {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (s.emergency.pausedRewards) revert RewardsAlreadyPaused();

        s.emergency.pausedRewards = true;
        s.emergency.pausedRewardsAt = uint64(block.timestamp);
        emit RewardsPaused(msg.sender, block.timestamp);
    }

    /// @notice Resume reward minting
    function resumeRewards() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        if (!s.emergency.pausedRewards) revert RewardsNotPaused();

        _validateResumeAuth(s, s.emergency.pausedRewardsAt);

        s.emergency.pausedRewards = false;
        s.emergency.pausedRewardsAt = 0;
        emit RewardsResumed(msg.sender, block.timestamp);
    }

    /// @notice Emergency: pause everything at once
    function pauseAll() external onlySecurityCouncil {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        uint64 now_ = uint64(block.timestamp);

        s.emergency.pausedReferrals = true;
        s.emergency.pausedAgents = true;
        s.emergency.pausedRewards = true;
        s.emergency.pausedReferralsAt = now_;
        s.emergency.pausedAgentsAt = now_;
        s.emergency.pausedRewardsAt = now_;

        emit ReferralsPaused(msg.sender, block.timestamp);
        emit AgentsPaused(msg.sender, block.timestamp);
        emit RewardsPaused(msg.sender, block.timestamp);
    }

    /// @notice Resume everything at once
    /// @dev Uses the earliest (longest paused) timestamp for DAO threshold check
    function resumeAll() external {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();

        // Use the earliest pause timestamp (longest paused state) for DAO check
        uint64 earliest = s.emergency.pausedReferralsAt;
        if (s.emergency.pausedAgentsAt != 0 && (earliest == 0 || s.emergency.pausedAgentsAt < earliest)) {
            earliest = s.emergency.pausedAgentsAt;
        }
        if (s.emergency.pausedRewardsAt != 0 && (earliest == 0 || s.emergency.pausedRewardsAt < earliest)) {
            earliest = s.emergency.pausedRewardsAt;
        }
        _validateResumeAuth(s, earliest);

        s.emergency.pausedReferrals = false;
        s.emergency.pausedAgents = false;
        s.emergency.pausedRewards = false;
        s.emergency.pausedReferralsAt = 0;
        s.emergency.pausedAgentsAt = 0;
        s.emergency.pausedRewardsAt = 0;

        emit ReferralsResumed(msg.sender, block.timestamp);
        emit AgentsResumed(msg.sender, block.timestamp);
        emit RewardsResumed(msg.sender, block.timestamp);
    }

    // ========================================================================
    // CIRCUIT BREAKER
    // ========================================================================

    /// @notice Checks and updates the circuit breaker for minting
    /// @param mintAmount Amount of FIX being minted
    /// @dev Auto-pauses rewards if hourly threshold exceeded
    function _checkCircuitBreaker(uint256 mintAmount) internal {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.EmergencyState storage em = s.emergency;

        // Reset hourly counter if needed
        if (block.timestamp - em.hourStartedAt > 1 hours) {
            em.mintedThisHour = 0;
            em.hourStartedAt = uint64(block.timestamp);
        }

        em.mintedThisHour += mintAmount;

        // Trigger circuit breaker if threshold exceeded
        if (em.mintedThisHour > em.circuitBreakerThreshold) {
            em.pausedRewards = true;
            em.pausedRewardsAt = uint64(block.timestamp);
            emit CircuitBreakerTriggered("Excessive minting", em.mintedThisHour);
        }

        // Also check daily aggregate ceiling
        _checkDailyMintCap(mintAmount);
    }

    /// @notice Checks daily aggregate mint ceiling
    /// @param mintAmount Amount of FIX being minted in this transaction
    /// @dev Auto-pauses rewards if daily ceiling exceeded. Resets every 24 hours.
    function _checkDailyMintCap(uint256 mintAmount) internal {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.EmergencyState storage em = s.emergency;

        // Reset daily counter if 24 hours have passed
        if (block.timestamp - em.dayStartedAt > 1 days) {
            em.mintedToday = 0;
            em.dayStartedAt = uint64(block.timestamp);
        }

        em.mintedToday += mintAmount;

        // Trigger daily ceiling if exceeded
        if (em.mintedToday > MAX_DAILY_MINT) {
            em.pausedRewards = true;
            em.pausedRewardsAt = uint64(block.timestamp);
            emit DailyMintCeilingTriggered(em.mintedToday);
        }
    }

    /// @notice Update the circuit breaker threshold
    /// @param newThreshold New maximum FIX tokens per hour
    /// @dev Cannot be set below MIN_CIRCUIT_BREAKER to prevent disabling
    function setCircuitBreakerThreshold(uint256 newThreshold) external onlySecurityCouncilOrGovernance {
        if (newThreshold < MIN_CIRCUIT_BREAKER) revert ThresholdBelowMinimum();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        uint256 oldThreshold = s.emergency.circuitBreakerThreshold;
        s.emergency.circuitBreakerThreshold = newThreshold;
        emit CircuitBreakerThresholdUpdated(oldThreshold, newThreshold);
    }

    // ========================================================================
    // ADMIN
    // ========================================================================

    /// @notice Update the security council address
    /// @param newCouncil New security council multisig
    function setSecurityCouncil(address newCouncil) external onlySecurityCouncilOrGovernance {
        if (newCouncil == address(0)) revert ZeroAddress();

        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        address oldCouncil = s.emergency.securityCouncil;
        s.emergency.securityCouncil = newCouncil;
        emit SecurityCouncilUpdated(oldCouncil, newCouncil);
    }

    /// @notice Update the DAO governance address
    /// @param newGovernance New governance contract address
    function setGovernance(address newGovernance) external onlySecurityCouncilOrGovernance {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        address oldGovernance = s.emergency.governance;
        s.emergency.governance = newGovernance;
        emit GovernanceUpdated(oldGovernance, newGovernance);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /// @notice Get the current emergency state
    function getEmergencyState()
        external
        view
        returns (
            bool pausedReferrals_,
            bool pausedAgents_,
            bool pausedRewards_,
            uint256 pausedReferralsAt_,
            uint256 pausedAgentsAt_,
            uint256 pausedRewardsAt_,
            uint256 circuitBreakerThreshold_,
            uint256 mintedThisHour_,
            address securityCouncil_,
            address governance_
        )
    {
        FixerRegistryStorage.MainStorage storage s = FixerRegistryStorage.getStorage();
        FixerRegistryStorage.EmergencyState storage em = s.emergency;

        return (
            em.pausedReferrals,
            em.pausedAgents,
            em.pausedRewards,
            em.pausedReferralsAt,
            em.pausedAgentsAt,
            em.pausedRewardsAt,
            em.circuitBreakerThreshold,
            em.mintedThisHour,
            em.securityCouncil,
            em.governance
        );
    }

    // ========================================================================
    // INTERNAL
    // ========================================================================

    /// @notice Validates that the caller has authority to resume
    /// @dev Security council can resume within 7 days; after that only DAO
    /// @param s The main storage reference
    /// @param pausedAt_ The per-state timestamp when this specific function was paused
    function _validateResumeAuth(FixerRegistryStorage.MainStorage storage s, uint64 pausedAt_) internal view {
        FixerRegistryStorage.EmergencyState storage em = s.emergency;

        if (block.timestamp - pausedAt_ > PAUSE_DAO_THRESHOLD) {
            // After 7 days, only governance can resume
            if (msg.sender != em.governance) revert DAOVoteRequiredForResume();
        } else {
            // Within 7 days, security council can resume
            if (
                msg.sender != em.securityCouncil &&
                msg.sender != em.governance
            ) {
                revert NotSecurityCouncilOrGovernance();
            }
        }
    }
}
