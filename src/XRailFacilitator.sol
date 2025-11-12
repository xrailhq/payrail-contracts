// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IX402Facilitator} from "./IX402Facilitator.sol";
import {ICreditableSettle} from "./ICreditableSettle.sol";

/**
 * @title XRailFacilitator
 * @notice Credit system for facilitator
 * @dev Decorates ERC-3009 transferWithAuthorization with automatic credit deduction
 * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
 */
contract XRailFacilitator is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    IX402Facilitator,
    ICreditableSettle
{
    // Credits use same decimals as USDC (6)
    uint8 public constant DECIMALS = 6;

    // Role for granting credits (e.g., Airdrop contract)
    bytes32 public constant CREDIT_GRANTER_ROLE = keccak256("CREDIT_GRANTER_ROLE");

    /// @custom:storage-location erc7201:xrail.storage.XRailFacilitator
    struct XRailFacilitatorStorage {
        // USDC contract (supports ERC-3009)
        IERC20 usdcToken;
        // Credit balances (stored with 6 decimals, same as USDC)
        mapping(address => uint256) credits;
        // Price per settlement (stored with 6 decimals, same as USDC)
        uint256 pricePerSettle;
    }

    // ERC-7201 storage location (see storage_verification.md for calculation steps)
    // keccak256(abi.encode(uint256(keccak256("xrail.storage.XRailFacilitator")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant XRAIL_FACILITATOR_STORAGE_LOCATION =
        0xf2b3e6d407b08b6813146209f6bbbe0e67f1fd7d721f7f82083049746af15500;

    function _getXRailFacilitatorStorage() private pure returns (XRailFacilitatorStorage storage $) {
        assembly {
            $.slot := XRAIL_FACILITATOR_STORAGE_LOCATION
        }
    }

    // Events
    event CreditsPurchased(address indexed buyer, uint256 amount, uint256 newBalance);

    event CreditUsed(address indexed user, bytes32 indexed paymentHash, uint256 remainingCredits);

    event SettlementExecuted(
        address indexed from,
        address indexed recipient,
        uint256 amount,
        uint256 facilitatorFee,
        bool success,
        uint256 timestamp
    );

    event UsdcAddressUpdated(address indexed previousUsdc, address indexed newUsdc);

    event PricePerSettleUpdated(uint256 previousPrice, uint256 newPrice);

    event CreditsGranted(address indexed grantee, uint256 amount, uint256 newBalance);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor for upgradeable pattern)
     * @param _owner Address of the contract owner
     * @param _pricePerSettle Initial price per settlement (in USDC base units, 6 decimals)
     */
    function initialize(address _owner, uint256 _pricePerSettle) public initializer {
        require(_pricePerSettle > 0, "Price must be positive");

        __Ownable_init(_owner);
        __AccessControl_init();

        // Grant DEFAULT_ADMIN_ROLE to owner so they can manage roles
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        $.pricePerSettle = _pricePerSettle;
    }

    /**
     * @notice Set the USDC token address
     * @param _usdc Address of the USDC token contract
     */
    function setUsdcAddress(address _usdc) external onlyOwner {
        require(_usdc != address(0), "Invalid USDC address");
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        address previousUsdc = address($.usdcToken);
        $.usdcToken = IERC20(_usdc);
        emit UsdcAddressUpdated(previousUsdc, _usdc);
    }

    /**
     * @notice Initialize AccessControl for existing proxy instances (upgrade only)
     * @dev Use reinitializer(2) to allow calling once after upgrading from v1 to v2
     * @dev Call this immediately after upgrading existing proxies to enable role-based access
     */
    function initializeAccessControl() external reinitializer(2) {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, owner());
    }

    /**
     * @notice Execute a payment settlement using EIP-3009 transferWithAuthorization
     * @dev Always deducts pricePerSettle as facilitator fee
     * @dev If to == address(this): Buys credits (1 USDC = 1 credit), then deducts fee
     * @dev If to != address(this): Deducts fee and executes USDC transfer
     * @dev Replay protection is handled by USDC's ERC-3009 nonce mechanism
     * @dev No reentrancy guard needed: USDC is a trusted contract with no callback hooks
     * @param from Address that signed the USDC payment authorization
     * @param to Final recipient of the USDC payment (or address(this) for buying credits)
     * @param value USDC amount to transfer
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
    ) external returns (bool success) {
        require(value > 0, "Value must be positive");

        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        uint256 fee = pricePerSettle();

        if (to == address(this)) {
            // Buying credits: transfer USDC to contract, credit the sender, then deduct fee
            require(value >= fee, "Value must be at least fee");

            (bool transferSuccess,) = address($.usdcToken)
                .call(
                    abi.encodeWithSignature(
                        "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)",
                        from,
                        address(this),
                        value,
                        validAfter,
                        validBefore,
                        nonce,
                        signature
                    )
                );

            require(transferSuccess, "USDC transfer failed");

            // Credit the full amount, then deduct the fee
            $.credits[from] += value;
            $.credits[from] -= fee;

            emit CreditsPurchased(from, value, $.credits[from]);
            emit SettlementExecuted(from, to, value, fee, true, block.timestamp);
        } else {
            // Normal settlement: deduct fee and transfer USDC
            require($.credits[from] >= fee, "Insufficient credits");

            $.credits[from] -= fee;

            (bool transferSuccess,) = address($.usdcToken)
                .call(
                    abi.encodeWithSignature(
                        "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)",
                        from,
                        to,
                        value,
                        validAfter,
                        validBefore,
                        nonce,
                        signature
                    )
                );

            require(transferSuccess, "Transfer failed");
            emit CreditUsed(from, nonce, $.credits[from]);
            emit SettlementExecuted(from, to, value, fee, true, block.timestamp);
        }

        return true;
    }

    /**
     * @notice Grant credits to an address (owner or CREDIT_GRANTER_ROLE only)
     * @param grantee address to receive credits
     * @param amount amount of credits to grant
     */
    function grantCredits(address grantee, uint256 amount) external {
        require(msg.sender == owner() || hasRole(CREDIT_GRANTER_ROLE, msg.sender), "Not authorized to grant credits");
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        $.credits[grantee] += amount;
        emit CreditsGranted(grantee, amount, $.credits[grantee]);
    }

    /**
     * @notice Check credit balance
     */
    function balanceOf(address user) external view returns (uint256) {
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        return $.credits[user];
    }

    /**
     * @notice Get the facilitator's price per transaction
     * @return price credit amount charged per settlement (6 decimals)
     */
    function pricePerSettle() public view returns (uint256) {
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        return $.pricePerSettle;
    }

    /**
     * @notice Update the price per settlement (owner only)
     * @param _newPrice New price per settlement (in USDC base units, 6 decimals)
     */
    function setPricePerSettle(uint256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "Price must be positive");

        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        uint256 previousPrice = $.pricePerSettle;
        $.pricePerSettle = _newPrice;

        emit PricePerSettleUpdated(previousPrice, _newPrice);
    }

    /**
     * @notice Withdraw accumulated USDC (owner only)
     */
    function withdrawRevenue() external onlyOwner {
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        uint256 balance = $.usdcToken.balanceOf(address(this));
        require(balance > 0, "No revenue to withdraw");

        require($.usdcToken.transfer(owner(), balance), "Withdrawal failed");
    }

    /**
     * @notice Get the USDC token address used by this facilitator
     * @return usdc Address of the USDC token contract
     */
    function usdc() external view returns (address) {
        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        return address($.usdcToken);
    }

    /**
     * @notice Update USDC token address (owner only)
     * @dev Allows flexibility if USDC contract is upgraded or deployed on new chain
     * @param _newUsdc Address of the new USDC token contract
     */
    function setUsdc(address _newUsdc) external onlyOwner {
        require(_newUsdc != address(0), "Invalid USDC address");

        XRailFacilitatorStorage storage $ = _getXRailFacilitatorStorage();
        address previousUsdc = address($.usdcToken);
        $.usdcToken = IERC20(_newUsdc);

        emit UsdcAddressUpdated(previousUsdc, _newUsdc);
    }

    /**
     * @notice Authorize upgrade to new implementation (UUPS requirement)
     * @dev Only owner can authorize upgrades
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
