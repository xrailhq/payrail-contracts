// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IX402Facilitator
 * @notice Standard interface for x402 payment facilitators
 * @dev Facilitators implement this interface to provide compatible settlement services
 */
interface IX402Facilitator {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a settlement is executed
     * @param from Address that signed the USDC payment authorization
     * @param to Final recipient of the USDC payment
     * @param amount USDC amount transferred (excluding facilitator fee)
     * @param facilitatorFee Fee charged by facilitator
     * @param success Whether the settlement succeeded
     * @param timestamp Block timestamp
     */
    event SettlementExecuted(
        address from,
        address to,
        address indexed recipient,
        uint256 amount,
        uint256 facilitatorFee,
        bool success,
        uint256 timestamp
    );

    // ============================================
    // CORE SETTLEMENT
    // ============================================

    /**
     * @notice Execute a payment settlement using EIP-3009 transferWithAuthorization
     * @dev Facilitator charges fee via USDC.transferFrom(client, facilitator, fee)
     * @param from Address that signed the USDC payment authorization
     * @param to Final recipient of the USDC payment
     * @param value USDC amount to transfer (excluding facilitator fee)
     * @param validAfter EIP-3009 authorization valid after timestamp
     * @param validBefore EIP-3009 authorization valid before timestamp
     * @param nonce Unique nonce for EIP-3009 replay protection
     * @param signature EIP-3009 signature from payer
     * @return success Whether the settlement succeeded
     */
    function settle(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external returns (bool success);
}
