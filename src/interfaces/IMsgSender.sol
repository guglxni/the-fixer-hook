// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title IMsgSender
/// @notice Interface for trusted routers that expose the actual transaction initiator
/// @dev Uniswap v4 routers pass themselves as `sender` to hooks. This interface
///      allows hooks to query the authenticated end-user behind the router call.
///      Required for correct user identification with Smart Accounts (ERC-4337)
///      and bundled transactions where `tx.origin` is unreliable.
interface IMsgSender {
    /// @notice Returns the address of the actual user who initiated the swap
    /// @return The authenticated end-user address
    function msgSender() external view returns (address);
}
