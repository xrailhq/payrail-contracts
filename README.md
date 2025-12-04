# XRail Contracts

Smart contracts for XRail's facilitator payment infrastructure powered by the X-402 protocol.

## Overview

**XRailFacilitator**: Upgradeable credit management system for USDC-based payments with configurable per-transaction pricing.

### Features

- **Credit System**: 1 USDC = 1 credit (1:1 ratio, both use 6 decimals)
- **Configurable Pricing**: Owner can adjust `pricePerSettle` fee per transaction
- **Gasless Transfers**: Uses EIP-3009 for USDC transfers without gas fees
- **Upgradeable**: ERC-1967 proxy pattern for future improvements
- **ERC-7201 Storage**: Namespaced storage pattern for upgrade safety

### Deployed Addresses

Deployed on **Sepolia** and **Base** networks:

| Contract | Address |
|----------|---------|
| Deployer | `0x460216e025231C89ff946f6BA24B7003CB88419F` |
| Airdrop | `0x9C4d953cf049955B1122959DFCb7e8A994a83197` |
| Facilitator Implementation | `0xE95FB33C09e20275740C311f3f4c259543c5D284` |
| Facilitator Proxy | `0xb5fcF9c691E0043c71692b5aEc8352b541BbC65F` |

**Network Links:**
- Sepolia: [Etherscan](https://sepolia.etherscan.io/address/0xb5fcF9c691E0043c71692b5aEc8352b541BbC65F)
- Base: [BaseScan](https://basescan.org/address/0xb5fcF9c691E0043c71692b5aEc8352b541BbC65F)

### Usage Flow

```
Step 1: Purchase Credits
─────────────────────────
User buys credits by sending USDC to the facilitator contract.
Amount sent is credited, then the fee is deducted.

  User → signs EIP-3009 authorization (to = facilitator)
      → Facilitator calls settle()
      → USDC transferred to contract
      → Credits added: credited amount - fee

  Example: Send 400 USDC → get 400 credits → 200 fee = 200 net credits
           (enough for 1 transaction at 200 fee)

Step 2: Make Payments
─────────────────────────
User makes payment for a resource. Facilitator settles it.
Credit is deducted and USDC payment is executed atomically.

  User → signs EIP-3009 authorization (to = recipient)
      → Facilitator calls settle()
      → Deduct pricePerSettle from user's credits
      → Execute USDC payment to recipient
      → Payment complete

Benefits:
• Configurable pricing: Owner can adjust fees as needed
• Gasless: Users sign EIP-3009 authorizations (no gas)
• Atomic: Credit deduction + payment in one transaction
• Transparent: All balances verifiable on-chain
```

### Contract Interface

```solidity
interface IX402Facilitator {
    function settle(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external returns (bool success);

    function pricePerSettle() external view returns (uint256);
}

interface ICreditableSettle {
    function balanceOf(address user) external view returns (uint256);
}
```

## Development

Built with [Foundry](https://book.getfoundry.sh/).

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

Deploy implementation + proxy with initialization:

```shell
forge script script/XRailFacilitator.s.sol:XRailFacilitatorScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# Set environment variables:
# USDC_ADDRESS - USDC token contract address
# OWNER_ADDRESS - Contract owner address
# DEPLOYER_PRIVATE_KEY - Deployment key
```

The deployment script will:
1. Deploy the implementation contract
2. Deploy an ERC1967 proxy
3. Initialize with USDC address, owner, and pricePerSettle (200)

### Upgrade

To upgrade to a new implementation:

```shell
forge script script/XRailFacilitator.s.sol:XRailFacilitatorUpgradeScript \
  --rpc-url $RPC_URL \
  --broadcast

# Set environment variables:
# PROXY_ADDRESS - Existing proxy address
# OWNER_PRIVATE_KEY - Owner's private key
```

### Format

```shell
forge fmt
```

## Architecture

### Storage Pattern

Uses ERC-7201 namespaced storage to prevent storage collisions during upgrades:

```solidity
// Storage location: keccak256(abi.encode(uint256(keccak256("xrail.storage.XRailFacilitator")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant XRailFacilitatorStorageLocation =
    0xf2b3e6d407b08b6813146209f6bbbe0e67f1fd7d721f7f82083049746af15500;
```

See `storage_verification.md` for calculation verification.

### Upgradeability

The contract uses OpenZeppelin's upgradeable contracts:
- `Initializable` - Replaces constructor for proxy pattern
- `OwnableUpgradeable` - Access control for admin functions
- ERC-1967 Proxy - Standard proxy pattern

All state is stored in the proxy, implementation can be upgraded while preserving data.

## Security

- **EIP-3009**: USDC's `transferWithAuthorization` provides replay protection via nonces
- **No Reentrancy Guard Needed**: USDC is a trusted contract with no callback hooks
- **Upgrade Safety**: ERC-7201 namespaced storage prevents collisions
- **Access Control**: Critical functions (owner-only) for price updates and withdrawals

## License

MIT
