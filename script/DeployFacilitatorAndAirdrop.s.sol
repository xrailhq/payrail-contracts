// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {XRailFacilitator} from "../src/XRailFacilitator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Airdrop} from "../src/Airdrop.sol";
import {Deployer} from "../src/Deployer.sol";

/**
 * @title DeployFacilitatorAndAirdrop
 * @notice Forge script to deploy XRailFacilitator (UUPS proxy) and Airdrop contract
 * @dev This script performs a complete deployment of the facilitator-airdrop system:
 *      1. Deploys XRailFacilitator implementation with CREATE2 (deterministic)
 *      2. Deploys ERC1967 proxy pointing to the implementation
 *      3. Initializes the proxy with USDC address, owner, and settle price
 *      4. Deploys Airdrop contract linked to the facilitator
 *      5. Grants CREDIT_GRANTER_ROLE to the Airdrop contract
 *
 * Usage:
 *   forge script script/DeployFacilitatorAndAirdrop.s.sol:DeployFacilitatorAndAirdrop \
 *     --rpc-url <RPC_URL> --broadcast --verify
 *
 * Required Environment Variables:
 *   Airdrop Configuration:
 *     AIRDROP_ADMIN_ADDRESS      - Address that can manage airdrop settings
 *     AIRDROP_INITIATOR_ADDRESS  - Address that can initiate airdrops
 *     AIRDROP_AMOUNT             - Amount of credits to airdrop per user
 *
 *   Facilitator Configuration:
 *     FACILITATOR_OWNER          - Address that will own the facilitator
 *     SETTLE_PRICE               - Price per settle operation (in USDC decimals)
 *     DEPLOYER_ADDRESS           - Address of the deployed Deployer contract
 *     PRIVATE_KEY                - Private key for deployment (or use --private-key flag)
 *
 * Post-Deployment:
 *   - Facilitator is deployed as upgradeable UUPS proxy
 *   - Airdrop has CREDIT_GRANTER_ROLE on the facilitator
 *   - Use the proxy address for all facilitator interactions
 *   - Implementation uses your Deployer contract for deterministic CREATE2 addresses
 */
contract DeployFacilitatorAndAirdrop is Script {
    function run() external returns (address proxyAddress, address airdropAddress) {
        Deployer deployer = Deployer(vm.envAddress("DEPLOYER_ADDRESS"));

        console.log("=== XRailFacilitator Deployment ===");
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        // 1. Deploy implementation
        console.log("\n[1/4] Deploying UUPS implementation via Deployer...");
        address implementation = address(deployFacilitator(deployer));
        console.log("Implementation deployed at:", implementation);

        // 2. Deploy proxy
        console.log("\n[2/4] Deploying ERC1967 proxy via Deployer...");
        {
            bytes memory initData = abi.encodeWithSelector(
                XRailFacilitator.initialize.selector, vm.envAddress("FACILITATOR_OWNER"), vm.envUint("SETTLE_PRICE")
            );
            proxyAddress = address(deployProxy(deployer, implementation, initData));
        }
        console.log("Proxy deployed at:", proxyAddress);

        // 3. Deploy airdrop
        console.log("\n[3/4] Deploying Airdrop via Deployer...");
        {
            airdropAddress = address(
                deployAirdrop(
                    deployer,
                    vm.envAddress("AIRDROP_ADMIN_ADDRESS"),
                    vm.envAddress("AIRDROP_INITIATOR_ADDRESS"),
                    proxyAddress,
                    vm.envUint("AIRDROP_AMOUNT")
                )
            );
        }
        console.log("Airdrop deployed at:", airdropAddress);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Proxy address:", proxyAddress);
        console.log("Airdrop address:", airdropAddress);

        console.log("\n=== Post-Deployment Actions Required ===");
        console.log("1. Set USDC address (run as FACILITATOR_OWNER):");
        console.log("   cast send", proxyAddress, "'setUsdcAddress(address)' <USDC_ADDRESS> --rpc-url <RPC_URL>");
        console.log("");
        console.log("2. Grant CREDIT_GRANTER_ROLE to Airdrop (run as FACILITATOR_OWNER):");
        console.log("   cast send", proxyAddress, "'grantRole(bytes32,address)'");
        console.log("   ", vm.toString(keccak256("CREDIT_GRANTER_ROLE")), airdropAddress);
        console.log("   --rpc-url <RPC_URL>");
    }

    /**
     * @notice Deploy ERC1967 proxy using Deployer contract
     * @dev Uses your Deployer contract for deterministic CREATE2 deployment across chains
     * @param deployer The Deployer contract instance
     * @param implementation The implementation contract address
     * @param initData The initialization data for the proxy
     * @return proxy The deployed ERC1967Proxy contract
     */
    function deployProxy(Deployer deployer, address implementation, bytes memory initData)
        internal
        returns (ERC1967Proxy)
    {
        bytes32 salt = keccak256("FacilitatorProxy:deploy:1");
        bytes memory creationCode = type(ERC1967Proxy).creationCode;
        bytes memory constructorArgs = abi.encode(implementation, initData);

        address proxyAddress = deployer.deployWithArgs(creationCode, constructorArgs, salt);
        console.log("Deployed proxy via Deployer with salt:", vm.toString(salt));

        return ERC1967Proxy(payable(proxyAddress));
    }

    /**
     * @notice Deploy XRailFacilitator implementation using Deployer contract
     * @dev Uses your Deployer contract for deterministic CREATE2 deployment across chains
     * @param deployer The Deployer contract instance
     * @return implementation The deployed XRailFacilitator implementation contract
     */
    function deployFacilitator(Deployer deployer) internal returns (XRailFacilitator) {
        bytes32 salt = keccak256("Facilitator:deploy:1");
        bytes memory bytecode = type(XRailFacilitator).creationCode;

        address implementationAddress = deployer.deploy(bytecode, salt);
        console.log("Deployed via Deployer with salt:", vm.toString(salt));

        return XRailFacilitator(implementationAddress);
    }

    /**
     * @notice Deploy Airdrop contract using Deployer contract
     * @dev Uses your Deployer contract for deterministic CREATE2 deployment across chains
     * @param deployer The Deployer contract instance
     * @param airdropAdminAddress Admin address for the airdrop
     * @param airdropInitiatorAddress Initiator address for the airdrop
     * @param facilitatorAddress Facilitator contract address
     * @param airdropAmount Amount to airdrop
     * @return airdrop The deployed Airdrop contract
     */
    function deployAirdrop(
        Deployer deployer,
        address airdropAdminAddress,
        address airdropInitiatorAddress,
        address facilitatorAddress,
        uint256 airdropAmount
    ) internal returns (Airdrop) {
        bytes32 salt = keccak256("Airdrop:deploy:1");
        bytes memory creationCode = type(Airdrop).creationCode;
        bytes memory constructorArgs =
            abi.encode(airdropAdminAddress, airdropInitiatorAddress, facilitatorAddress, airdropAmount);

        address airdropAddress = deployer.deployWithArgs(creationCode, constructorArgs, salt);
        console.log("Deployed Airdrop via Deployer with salt:", vm.toString(salt));

        return Airdrop(airdropAddress);
    }
}
