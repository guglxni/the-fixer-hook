// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title HookMiner
/// @notice Utility library for finding valid hook deployment addresses
/// @dev Uniswap v4 hooks must be deployed at addresses with specific bits set
///      based on which hook functions are enabled. This library finds valid
///      addresses using CREATE2 salt mining.
library HookMiner {
    
    /// @notice Find a valid hook address using CREATE2 salt mining
    /// @param deployer The address that will deploy the hook
    /// @param flags The required permission flags (bits that must be set)
    /// @param creationCode The contract creation code (type(Contract).creationCode)
    /// @param constructorArgs The ABI-encoded constructor arguments
    /// @return hookAddress The valid hook address found
    /// @return salt The salt to use with CREATE2
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        
        // Try salts until we find a valid address
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, initCodeHash);
            
            // Check if the address has the required permission bits set
            if (uint160(hookAddress) & flags == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: No valid address found within iteration limit");
    }
    
    /// @notice Compute the CREATE2 address for a given deployer, salt, and init code hash
    /// @param deployer The address that will deploy via CREATE2
    /// @param salt The CREATE2 salt
    /// @param initCodeHash The keccak256 hash of the init code
    /// @return The computed address
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
    
    /// @notice Validate that an address has the required permission flags
    /// @param hookAddress The address to validate
    /// @param flags The required permission flags
    /// @return True if the address has all required flags set
    function validateAddress(
        address hookAddress,
        uint160 flags
    ) internal pure returns (bool) {
        return uint160(hookAddress) & flags == flags;
    }
}
