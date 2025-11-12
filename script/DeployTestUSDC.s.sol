// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestUSDC.sol";

/**
 * @title DeployTestUSDC
 * @notice Deployment script for TestUSDC contract on Anvil
 * @dev Run with: forge script script/DeployTestUSDC.s.sol --rpc-url http://localhost:8545 --broadcast
 */
contract DeployTestUSDC is Script {
    function run() external returns (TestUSDC) {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy TestUSDC

        bytes32 salt = keccak256("initial deployment");

        TestUSDC usdc = new TestUSDC{salt: salt}();

        console.log("TestUSDC deployed at:", address(usdc));
        console.log("Deployer balance:", usdc.balanceOf(msg.sender) / 10 ** 6, "USDC");

        vm.stopBroadcast();

        return usdc;
    }
}
