// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICreditableSettle
 * @notice Interface for credit-based settlement systems
 * @dev Defines view functions for getting settlement price and USDC address
 */
interface ICreditableSettle {
    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get the facilitator's price per transaction
     * @return pricePerSettle credit amount charged per settlement (6 decimals)
     */
    function pricePerSettle() external view returns (uint256);

    /**
     * @notice Get the USDC token address used by this facilitator
     * @return usdc Address of the USDC token contract
     */
    function usdc() external view returns (address);
}
