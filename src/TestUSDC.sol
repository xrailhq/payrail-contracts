// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title TestUSDC
 * @notice Minimal USDC implementation with transferWithAuthorization (EIP-3009) for testing
 * @dev This is a simplified version for local testing with Anvil
 */
contract TestUSDC is ERC20, EIP712 {
    // EIP-3009 typehash for transferWithAuthorization
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    // EIP-3009 typehash for receiveWithAuthorization
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    // Track used authorizations to prevent replay attacks
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    constructor() ERC20("Test USD Coin", "USDC") EIP712("Test USD Coin", "1") {
        // Mint 1 million USDC (with 6 decimals) to deployer for testing
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    /**
     * @notice USDC uses 6 decimals instead of 18
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Mint tokens for testing purposes
     * @param to Address to mint tokens to
     * @param amount Amount to mint (with 6 decimals)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Check if an authorization has been used
     * @param authorizer Authorizer's address
     * @param nonce Nonce of the authorization
     * @return True if authorization is used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @notice Execute a transfer with a signed authorization (EIP-3009)
     * @dev Matches Circle's USDC interface: signature is packed as r + s + v (65 bytes)
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix timestamp)
     * @param validBefore The time before which this is valid (unix timestamp)
     * @param nonce Unique nonce
     * @param signature ECDSA signature (65 bytes: r + s + v)
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        require(signature.length == 65, "TestUSDC: invalid signature length");

        // Split signature into v, r, s (signature is packed as r + s + v)
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        _transferWithAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, v, r, s
        );
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer (EIP-3009)
     * @dev This has an additional check to ensure that the payee's address matches
     * the caller of this function to prevent front-running attacks.
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix timestamp)
     * @param validBefore The time before which this is valid (unix timestamp)
     * @param nonce Unique nonce
     * @param signature ECDSA signature (65 bytes: r + s + v)
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        require(to == msg.sender, "TestUSDC: caller must be the payee");
        require(signature.length == 65, "TestUSDC: invalid signature length");

        // Split signature into v, r, s
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        _transferWithAuthorization(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, v, r, s
        );
    }

    /**
     * @notice Internal function to execute a transfer with authorization
     */
    function _transferWithAuthorization(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(block.timestamp > validAfter, "TestUSDC: authorization not yet valid");
        require(block.timestamp < validBefore, "TestUSDC: authorization expired");
        require(!_authorizationStates[from][nonce], "TestUSDC: authorization already used");

        // Verify EIP-712 signature
        bytes32 structHash = keccak256(abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);

        require(signer == from, "TestUSDC: invalid signature");

        // Mark authorization as used
        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        // Execute transfer
        _transfer(from, to, value);
    }
}
