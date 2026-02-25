// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IAgentRegistry} from "../../src/interfaces/IAgentRegistry.sol";

/// @title IFixerRegistryFull
/// @notice Combined interface for test casting — includes agent + EIP-3009 + XMTP functions
/// @dev Used in tests to call extension functions through the proxy's fallback().
///      Not used in production — cast to this interface for test convenience only.
interface IFixerRegistryFull is IAgentRegistry {
    // EIP-3009
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function TRANSFER_WITH_AUTHORIZATION_TYPEHASH() external view returns (bytes32);
}
