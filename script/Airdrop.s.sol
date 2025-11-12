// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Airdrop} from "../src/Airdrop.sol";
import {XRailFacilitator} from "../src/XRailFacilitator.sol";

/**
 * @title AirdropDeploymentScript
 * @notice Script for deploying Airdrop contract and setting up permissions
 * @dev This script:
 *      1. Deploys the Airdrop contract
 *      2. Grants CREDIT_GRANTER_ROLE to the Airdrop contract in XRailFacilitator
 *
 * Usage:
 *   forge script script/Airdrop.s.sol:AirdropDeploymentScript \
 *     --rpc-url <RPC_URL> --broadcast --verify
 *
 * Environment Variables (Required):
 *   ADMIN_ADDRESS - Address of the airdrop admin
 *   AIRDROP_INITIATOR_ADDRESS - Address authorized to initiate airdrops
 *   FACILITATOR_ADDRESS - Address of the XRailFacilitator proxy
 *   AIRDROP_AMOUNT - Amount of credits to airdrop per user (in base units, 6 decimals)
 *   FACILITATOR_OWNER_PRIVATE_KEY - Private key of XRailFacilitator owner (to grant role)
 */
contract AirdropDeploymentScript is Script {
    function run() public {
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address airdropInitiatorAddress = vm.envAddress("AIRDROP_INITIATOR_ADDRESS");
        address facilitatorAddress = vm.envAddress("FACILITATOR_ADDRESS");
        uint256 airdropAmount = vm.envUint("AIRDROP_AMOUNT");

        console.log("=== Airdrop Deployment ===");
        console.log("Admin Address:", adminAddress);
        console.log("Airdrop Initiator Address:", airdropInitiatorAddress);
        console.log("Facilitator Address:", facilitatorAddress);
        console.log("Airdrop Amount:", airdropAmount);
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        // Step 1: Deploy Airdrop contract
        console.log("\n[1/2] Deploying Airdrop contract...");
        Airdrop airdrop = new Airdrop(adminAddress, airdropInitiatorAddress, facilitatorAddress, airdropAmount);
        console.log("Airdrop deployed at:", address(airdrop));

        vm.stopBroadcast();

        // Verification
        console.log("\n=== Deployment Verification ===");
        console.log("Airdrop admin:", airdrop.admin());
        console.log("Airdrop initiator:", airdrop.airdropInitiator());
        console.log("Airdrop facilitator:", address(airdrop.facilitator()));
        console.log("Airdrop amount:", airdrop.airdropAmount());

        console.log("\n=== Deployment Complete ===");
        console.log("Airdrop contract address:", address(airdrop));
        console.log("\nAdmin or AirdropInitiator can now call initAirdrop(address receiver) to distribute credits");
    }
}

/**
 * @title UpdateAirdropAmountScript
 * @notice Script to update the airdrop amount
 *
 * Usage:
 *   forge script script/Airdrop.s.sol:UpdateAirdropAmountScript \
 *     --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 *   AIRDROP_ADDRESS - Address of the Airdrop contract
 *   NEW_AIRDROP_AMOUNT - New amount of credits to airdrop per user
 *   ADMIN_PRIVATE_KEY - Private key of the admin
 */
contract UpdateAirdropAmountScript is Script {
    function run() public {
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        uint256 newAmount = vm.envUint("NEW_AIRDROP_AMOUNT");

        console.log("=== Update Airdrop Amount ===");
        console.log("Airdrop Address:", airdropAddress);
        console.log("New Amount:", newAmount);
        console.log("Admin:", msg.sender);

        vm.startBroadcast();

        Airdrop airdrop = Airdrop(airdropAddress);
        uint256 previousAmount = airdrop.airdropAmount();

        console.log("\nUpdating airdrop amount...");
        airdrop.setAirdropAmount(newAmount);
        console.log("Amount updated successfully");

        vm.stopBroadcast();

        console.log("\n=== Verification ===");
        console.log("Previous amount:", previousAmount);
        console.log("New amount:", airdrop.airdropAmount());
        console.log("\n=== Update Complete ===");
    }
}

/**
 * @title UpdateAirdropInitiatorScript
 * @notice Script to update the airdrop initiator address
 *
 * Usage:
 *   forge script script/Airdrop.s.sol:UpdateAirdropInitiatorScript \
 *     --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 *   AIRDROP_ADDRESS - Address of the Airdrop contract
 *   NEW_INITIATOR_ADDRESS - Address of the new airdrop initiator
 *   ADMIN_PRIVATE_KEY - Private key of the admin
 */
contract UpdateAirdropInitiatorScript is Script {
    function run() public {
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        address newInitiatorAddress = vm.envAddress("NEW_INITIATOR_ADDRESS");

        console.log("=== Update Airdrop Initiator ===");
        console.log("Airdrop Address:", airdropAddress);
        console.log("New Initiator Address:", newInitiatorAddress);
        console.log("Admin:", msg.sender);

        vm.startBroadcast();

        Airdrop airdrop = Airdrop(airdropAddress);
        address previousInitiator = airdrop.airdropInitiator();

        console.log("\nUpdating airdrop initiator...");
        airdrop.setAirdropInitiator(newInitiatorAddress);
        console.log("Initiator updated successfully");

        vm.stopBroadcast();

        console.log("\n=== Verification ===");
        console.log("Previous initiator:", previousInitiator);
        console.log("New initiator:", airdrop.airdropInitiator());
        console.log("\n=== Update Complete ===");
    }
}

/**
 * @title TransferAirdropAdminScript
 * @notice Script to transfer admin rights to a new address
 *
 * Usage:
 *   forge script script/Airdrop.s.sol:TransferAirdropAdminScript \
 *     --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 *   AIRDROP_ADDRESS - Address of the Airdrop contract
 *   NEW_ADMIN_ADDRESS - Address of the new admin
 *   CURRENT_ADMIN_PRIVATE_KEY - Private key of the current admin
 */
contract TransferAirdropAdminScript is Script {
    function run() public {
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        address newAdminAddress = vm.envAddress("NEW_ADMIN_ADDRESS");

        console.log("=== Transfer Airdrop Admin ===");
        console.log("Airdrop Address:", airdropAddress);
        console.log("New Admin Address:", newAdminAddress);
        console.log("Current Admin:", msg.sender);

        vm.startBroadcast();

        Airdrop airdrop = Airdrop(airdropAddress);
        address previousAdmin = airdrop.admin();

        console.log("\nTransferring admin rights...");
        airdrop.setAdmin(newAdminAddress);
        console.log("Admin transferred successfully");

        vm.stopBroadcast();

        console.log("\n=== Verification ===");
        console.log("Previous admin:", previousAdmin);
        console.log("New admin:", airdrop.admin());
        console.log("\n=== Transfer Complete ===");
    }
}

/**
 * @title RevokeAirdropRoleScript
 * @notice Script to revoke CREDIT_GRANTER_ROLE from Airdrop contract
 * @dev Use this when the airdrop campaign is complete
 *
 * Usage:
 *   forge script script/Airdrop.s.sol:RevokeAirdropRoleScript \
 *     --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 *   AIRDROP_ADDRESS - Address of the Airdrop contract
 *   FACILITATOR_ADDRESS - Address of the XRailFacilitator proxy
 *   FACILITATOR_OWNER_PRIVATE_KEY - Private key of XRailFacilitator owner
 */
contract RevokeAirdropRoleScript is Script {
    function run() public {
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        address facilitatorAddress = vm.envAddress("FACILITATOR_ADDRESS");

        console.log("=== Revoke Airdrop Role ===");
        console.log("Airdrop Address:", airdropAddress);
        console.log("Facilitator Address:", facilitatorAddress);
        console.log("Facilitator Owner:", msg.sender);

        vm.startBroadcast();

        XRailFacilitator facilitator = XRailFacilitator(facilitatorAddress);
        bytes32 granterRole = facilitator.CREDIT_GRANTER_ROLE();

        console.log("\nRevoking CREDIT_GRANTER_ROLE...");
        facilitator.revokeRole(granterRole, airdropAddress);
        console.log("Role revoked successfully");

        vm.stopBroadcast();

        console.log("\n=== Verification ===");
        console.log("Has CREDIT_GRANTER_ROLE:", facilitator.hasRole(granterRole, airdropAddress));
        console.log("\n=== Revocation Complete ===");
        console.log("Airdrop contract can no longer grant credits");
    }
}
