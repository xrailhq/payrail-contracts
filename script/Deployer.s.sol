// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../src/Deployer.sol";

/**
 * @title DeployerDeploymentScript
 * @notice Forge script to deploy the Deployer contract
 * @dev This script deploys the Deployer contract which enables CREATE2-based deterministic deployments
 *
 * Usage:
 *   forge script script/Deployer.s.sol:DeployerDeploymentScript --rpc-url <RPC_URL> --broadcast --verify
 *
 * Environment Variables:
 *   PRIVATE_KEY or use --private-key flag - The private key for deployment
 *
 * Post-Deployment:
 *   1. The deployer (msg.sender) becomes the owner
 *   2. Owner can authorize other addresses via authorizeDeployer(address)
 *   3. Use the same script on different chains to maintain consistent Deployer addresses (if using CREATE2 factory)
 */
contract DeployerDeploymentScript is Script {
    function run() public returns (address) {
        console.log("=== Deployer Deployment ===");
        console.log("Deploying from:", msg.sender);

        vm.startBroadcast();

        // Deploy the Deployer contract - msg.sender becomes the owner
        Deployer deployer = new Deployer();

        vm.stopBroadcast();

        console.log("Deployer contract deployed at:", address(deployer));
        console.log("Owner:", deployer.owner());

        return address(deployer);
    }
}
