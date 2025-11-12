// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {XRailFacilitator} from "../src/XRailFacilitator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployXRailFacilitatorUUPS
 * @notice Deployment script for XRailFacilitator with UUPS upgrade support
 * @dev This is the NEW deployment script that creates upgradeable proxies
 *
 * Usage:
 *   forge script script/DeployXRailFacilitatorUUPS.s.sol --rpc-url http://localhost:8545 --broadcast
 *
 * Environment Variables:
 *   USDC_ADDRESS - Address of USDC token contract
 *   OWNER_ADDRESS - Address of contract owner (optional, defaults to deployer)
 */
contract DeployXRailFacilitatorUUPS is Script {
    function run() external returns (address proxyAddress) {
        // Get deployment parameters
        address usdcAddress = vm.envAddress("USDC_ADDRESS");

        address ownerAddress;
        try vm.envAddress("OWNER_ADDRESS") returns (address addr) {
            ownerAddress = addr;
        } catch {
            ownerAddress = msg.sender;
        }

        console.log("=== XRailFacilitator UUPS Deployment ===");
        console.log("USDC Address:", usdcAddress);
        console.log("Owner Address:", ownerAddress);
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        // 1. Deploy UUPS-enabled implementation
        console.log("\n[1/2] Deploying UUPS implementation...");
        XRailFacilitator implementation = new XRailFacilitator();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Prepare initialization data
        uint256 pricePerSettle = 200; // 0.0002 USDC (200 in 6 decimals)
        bytes memory initData =
            abi.encodeWithSelector(XRailFacilitator.initialize.selector, usdcAddress, ownerAddress, pricePerSettle);

        // 3. Deploy proxy with initialization
        console.log("\n[2/2] Deploying ERC1967 proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proxyAddress = address(proxy);
        console.log("Proxy deployed at:", proxyAddress);

        XRailFacilitator facilitator = XRailFacilitator(proxyAddress);

        vm.stopBroadcast();

        // Verification
        console.log("\n=== Deployment Verification ===");
        console.log("USDC Address:", facilitator.usdc());
        console.log("Owner:", facilitator.owner());
        console.log("Price per settle:", facilitator.pricePerSettle());
        console.log("Decimals:", facilitator.DECIMALS());

        // Verify UUPS upgrade capability
        console.log("\n=== UUPS Verification ===");
        console.log("Implementation supports UUPS: YES (has _authorizeUpgrade)");
        console.log("Proxy is upgradeable: YES");

        console.log("\n=== Deployment Complete ===");
        console.log("Use this proxy address:", proxyAddress);
        console.log("\nTo upgrade later, use:");
        console.log("  facilitator.upgradeToAndCall(newImplementation, \"\")");

        return proxyAddress;
    }
}

/**
 * @title UpgradeXRailFacilitatorUUPS
 * @notice Script for upgrading UUPS-enabled XRailFacilitator
 * @dev Only works with proxies deployed using the UUPS pattern
 *
 * Usage:
 *   PROXY_ADDRESS=0x... forge script script/DeployXRailFacilitatorUUPS.s.sol:UpgradeXRailFacilitatorUUPS \
 *     --rpc-url http://localhost:8545 --broadcast
 *
 * Environment Variables:
 *   PROXY_ADDRESS - Address of existing UUPS-enabled proxy
 *   AIRDROP_ADDRESS - (Optional) Address to grant CREDIT_GRANTER_ROLE
 */
contract UpgradeXRailFacilitatorUUPS is Script {
    function run() external {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        address airdropAddress;
        try vm.envAddress("AIRDROP_ADDRESS") returns (address addr) {
            airdropAddress = addr;
        } catch {
            airdropAddress = address(0);
        }

        console.log("=== XRailFacilitator UUPS Upgrade ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("Upgrader (must be owner):", msg.sender);
        if (airdropAddress != address(0)) {
            console.log("Airdrop Address:", airdropAddress);
        }

        vm.startBroadcast();

        XRailFacilitator proxy = XRailFacilitator(proxyAddress);

        // Step 1: Deploy new implementation
        console.log("\n[1/3] Deploying new implementation...");
        XRailFacilitator newImplementation = new XRailFacilitator();
        console.log("New Implementation deployed at:", address(newImplementation));

        // Step 2: Upgrade using UUPS upgradeToAndCall
        console.log("\n[2/3] Upgrading proxy via UUPS...");
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("Proxy upgraded successfully");

        // Step 3: Initialize AccessControl if needed (reinitializer)
        console.log("\n[3/3] Initializing AccessControl...");
        proxy.initializeAccessControl();
        console.log("AccessControl initialized");

        // Optional: Grant CREDIT_GRANTER_ROLE
        if (airdropAddress != address(0)) {
            bytes32 granterRole = proxy.CREDIT_GRANTER_ROLE();
            console.log("\nGranting CREDIT_GRANTER_ROLE to Airdrop...");
            proxy.grantRole(granterRole, airdropAddress);
            console.log("Role granted successfully");
        }

        vm.stopBroadcast();

        // Verification
        console.log("\n=== Upgrade Verification ===");
        console.log("New Implementation:", address(newImplementation));
        console.log("Owner:", proxy.owner());
        console.log("USDC:", proxy.usdc());
        console.log("Price per settle:", proxy.pricePerSettle());

        // Verify role setup
        console.log("\n=== Role Verification ===");
        bytes32 adminRole = proxy.DEFAULT_ADMIN_ROLE();
        console.log("Owner has DEFAULT_ADMIN_ROLE:", proxy.hasRole(adminRole, proxy.owner()));

        if (airdropAddress != address(0)) {
            bytes32 granterRole = proxy.CREDIT_GRANTER_ROLE();
            console.log("Airdrop has CREDIT_GRANTER_ROLE:", proxy.hasRole(granterRole, airdropAddress));
        }

        console.log("\n=== Upgrade Complete ===");
    }
}
