// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Deployer
 * @notice A contract for deploying contracts with deterministic addresses using CREATE2
 * @dev This allows for the same contract address across multiple chains when using the same salt and bytecode
 * @dev Access control prevents address sniping while maintaining deterministic cross-chain deployments
 */
contract Deployer is Ownable {
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt, address indexed deployer);
    event DeployerAuthorized(address indexed deployer);
    event DeployerRevoked(address indexed deployer);

    error DeploymentFailed();
    error EmptyBytecode();
    error Unauthorized();

    mapping(address => bool) public authorizedDeployers;

    constructor() Ownable(msg.sender) {}

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    /**
     * @notice Authorize an address to deploy contracts
     * @param deployer The address to authorize
     */
    function authorizeDeployer(address deployer) external onlyOwner {
        authorizedDeployers[deployer] = true;
        emit DeployerAuthorized(deployer);
    }

    /**
     * @notice Revoke deployment authorization from an address
     * @param deployer The address to revoke authorization from
     */
    function revokeDeployer(address deployer) external onlyOwner {
        authorizedDeployers[deployer] = false;
        emit DeployerRevoked(deployer);
    }

    /**
     * @notice Deploy a contract using CREATE2
     * @param bytecode The creation bytecode of the contract to deploy
     * @param salt A salt value to determine the deployment address
     * @return deployedAddress The address of the deployed contract
     */
    function deploy(bytes memory bytecode, bytes32 salt) public onlyAuthorized returns (address deployedAddress) {
        if (bytecode.length == 0) revert EmptyBytecode();

        assembly {
            deployedAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        if (deployedAddress == address(0)) revert DeploymentFailed();

        emit ContractDeployed(deployedAddress, salt, msg.sender);
    }

    /**
     * @notice Compute the address where a contract will be deployed
     * @param bytecode The creation bytecode of the contract
     * @param salt The salt value
     * @return The address where the contract will be deployed
     */
    function computeAddress(bytes memory bytecode, bytes32 salt) public view returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Compute the address where a contract will be deployed using bytecode hash
     * @param bytecodeHash The keccak256 hash of the creation bytecode
     * @param salt The salt value
     * @return The address where the contract will be deployed
     */
    function computeAddressWithHash(bytes32 bytecodeHash, bytes32 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Deploy a contract with constructor arguments using CREATE2
     * @param creationCode The creation bytecode of the contract (without constructor args)
     * @param constructorArgs The ABI-encoded constructor arguments
     * @param salt A salt value to determine the deployment address
     * @return deployedAddress The address of the deployed contract
     */
    function deployWithArgs(bytes memory creationCode, bytes memory constructorArgs, bytes32 salt)
        public
        onlyAuthorized
        returns (address deployedAddress)
    {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        return deploy(bytecode, salt);
    }

    function _onlyAuthorized() internal {
        if (!authorizedDeployers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
    }
}
