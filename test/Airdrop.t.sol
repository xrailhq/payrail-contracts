// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Airdrop} from "../src/Airdrop.sol";
import {XRailFacilitator} from "../src/XRailFacilitator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock USDC for testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public constant DECIMALS = 6;

    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AirdropTest is Test {
    Airdrop public airdrop;
    XRailFacilitator public facilitator;
    MockUSDC public usdc;

    address public admin = address(0x1);
    address public facilitatorOwner = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public unauthorizedUser = address(0x6);
    address public airdropInitiator = address(0x7);

    uint256 public constant AIRDROP_AMOUNT = 10 * 10 ** 6; // 10 credits

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy XRailFacilitator
        XRailFacilitator implementation = new XRailFacilitator();
        uint256 pricePerSettle = 10 ** 6; // 1 USDC
        bytes memory initData =
            abi.encodeWithSelector(XRailFacilitator.initialize.selector, facilitatorOwner, pricePerSettle);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        facilitator = XRailFacilitator(address(proxy));

        // Set USDC address
        vm.prank(facilitatorOwner);
        facilitator.setUsdc(address(usdc));

        // Deploy Airdrop contract
        airdrop = new Airdrop(admin, airdropInitiator, address(facilitator), AIRDROP_AMOUNT);

        // Grant CREDIT_GRANTER_ROLE to Airdrop contract
        bytes32 granterRole = facilitator.CREDIT_GRANTER_ROLE();
        vm.prank(facilitatorOwner);
        facilitator.grantRole(granterRole, address(airdrop));
    }

    // ========================================
    // Constructor Tests
    // ========================================

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(airdrop.admin(), admin, "Admin should be set correctly");
        assertEq(address(airdrop.facilitator()), address(facilitator), "Facilitator should be set correctly");
        assertEq(airdrop.airdropAmount(), AIRDROP_AMOUNT, "Airdrop amount should be set correctly");
    }

    function test_Constructor_RevertsOnZeroAdminAddress() public {
        vm.expectRevert("Invalid admin address");
        new Airdrop(address(0), airdropInitiator, address(facilitator), AIRDROP_AMOUNT);
    }

    function test_Constructor_RevertsOnZeroFacilitatorAddress() public {
        vm.expectRevert("Invalid facilitator address");
        new Airdrop(admin, airdropInitiator, address(0), AIRDROP_AMOUNT);
    }

    function test_Constructor_RevertsOnZeroAirdropAmount() public {
        vm.expectRevert("Airdrop amount must be positive");
        new Airdrop(admin, airdropInitiator, address(facilitator), 0);
    }

    // ========================================
    // initAirdrop Tests
    // ========================================

    function test_InitAirdrop_AdminCanInitiate() public {
        // Admin initiates airdrop for user1
        vm.prank(admin);
        airdrop.initAirdrop(user1);

        // Verify user1 received credits
        assertEq(facilitator.balanceOf(user1), AIRDROP_AMOUNT, "User should receive airdrop credits");
        assertTrue(airdrop.hasClaimed(user1), "User should be marked as claimed");
    }

    function test_InitAirdrop_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit AirdropInitiated(user1, AIRDROP_AMOUNT);

        vm.prank(admin);
        airdrop.initAirdrop(user1);
    }

    function test_InitAirdrop_UnauthorizedUserCannotInitiate() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Not allowed to init Airdrop!");
        airdrop.initAirdrop(user1);

        // Verify no credits were granted
        assertEq(facilitator.balanceOf(user1), 0, "No credits should be granted");
        assertFalse(airdrop.hasClaimed(user1), "User should not be marked as claimed");
    }

    function test_InitAirdrop_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid receiver address");
        airdrop.initAirdrop(address(0));
    }

    function test_InitAirdrop_RevertsOnDoubleClaim() public {
        // First airdrop succeeds
        vm.prank(admin);
        airdrop.initAirdrop(user1);

        uint256 firstBalance = facilitator.balanceOf(user1);

        // Second airdrop should fail
        vm.prank(admin);
        vm.expectRevert("Airdrop already claimed");
        airdrop.initAirdrop(user1);

        // Balance should remain unchanged
        assertEq(facilitator.balanceOf(user1), firstBalance, "Balance should not change after failed claim");
    }

    function test_InitAirdrop_MultipleUsers() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        // Admin airdrops to multiple users
        vm.startPrank(admin);
        for (uint256 i = 0; i < users.length; i++) {
            airdrop.initAirdrop(users[i]);
        }
        vm.stopPrank();

        // Verify all users received credits
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(facilitator.balanceOf(users[i]), AIRDROP_AMOUNT, "Each user should receive airdrop credits");
            assertTrue(airdrop.hasClaimed(users[i]), "Each user should be marked as claimed");
        }
    }

    // ========================================
    // setAirdropAmount Tests
    // ========================================

    function test_SetAirdropAmount_AdminCanUpdate() public {
        uint256 newAmount = 20 * 10 ** 6; // 20 credits

        vm.prank(admin);
        airdrop.setAirdropAmount(newAmount);

        assertEq(airdrop.airdropAmount(), newAmount, "Airdrop amount should be updated");
    }

    function test_SetAirdropAmount_EmitsEvent() public {
        uint256 newAmount = 20 * 10 ** 6;

        vm.expectEmit(false, false, false, true);
        emit AirdropAmountUpdated(AIRDROP_AMOUNT, newAmount);

        vm.prank(admin);
        airdrop.setAirdropAmount(newAmount);
    }

    function test_SetAirdropAmount_UnauthorizedUserCannotUpdate() public {
        uint256 newAmount = 20 * 10 ** 6;

        vm.prank(unauthorizedUser);
        vm.expectRevert("Only admin can update airdrop amount");
        airdrop.setAirdropAmount(newAmount);

        assertEq(airdrop.airdropAmount(), AIRDROP_AMOUNT, "Airdrop amount should remain unchanged");
    }

    function test_SetAirdropAmount_RevertsOnZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert("Airdrop amount must be positive");
        airdrop.setAirdropAmount(0);
    }

    function test_SetAirdropAmount_AffectsFutureAirdrops() public {
        uint256 newAmount = 20 * 10 ** 6; // 20 credits

        // First airdrop with initial amount
        vm.prank(admin);
        airdrop.initAirdrop(user1);
        assertEq(facilitator.balanceOf(user1), AIRDROP_AMOUNT);

        // Update amount
        vm.prank(admin);
        airdrop.setAirdropAmount(newAmount);

        // Second airdrop with new amount
        vm.prank(admin);
        airdrop.initAirdrop(user2);
        assertEq(facilitator.balanceOf(user2), newAmount, "New user should receive updated amount");
    }

    // ========================================
    // setAdmin Tests
    // ========================================

    function test_SetAdmin_AdminCanUpdate() public {
        address newAdmin = address(0x7);

        vm.prank(admin);
        airdrop.setAdmin(newAdmin);

        assertEq(airdrop.admin(), newAdmin, "Admin should be updated");
    }

    function test_SetAdmin_EmitsEvent() public {
        address newAdmin = address(0x7);

        vm.expectEmit(true, true, false, false);
        emit AdminUpdated(admin, newAdmin);

        vm.prank(admin);
        airdrop.setAdmin(newAdmin);
    }

    function test_SetAdmin_UnauthorizedUserCannotUpdate() public {
        address newAdmin = address(0x7);

        vm.prank(unauthorizedUser);
        vm.expectRevert("Only admin can update admin");
        airdrop.setAdmin(newAdmin);

        assertEq(airdrop.admin(), admin, "Admin should remain unchanged");
    }

    function test_SetAdmin_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid admin address");
        airdrop.setAdmin(address(0));
    }

    function test_SetAdmin_NewAdminCanInitiateAirdrop() public {
        address newAdmin = address(0x7);

        // Transfer admin to newAdmin
        vm.prank(admin);
        airdrop.setAdmin(newAdmin);

        // Old admin cannot initiate anymore
        vm.prank(admin);
        vm.expectRevert("Not allowed to init Airdrop!");
        airdrop.initAirdrop(user1);

        // New admin can initiate
        vm.prank(newAdmin);
        airdrop.initAirdrop(user1);

        assertEq(facilitator.balanceOf(user1), AIRDROP_AMOUNT, "New admin should be able to airdrop");
    }

    // ========================================
    // hasClaimedAirdrop Tests
    // ========================================

    function test_HasClaimedAirdrop_ReturnsFalseInitially() public view {
        assertFalse(airdrop.hasClaimedAirdrop(user1), "User should not have claimed initially");
    }

    function test_HasClaimedAirdrop_ReturnsTrueAfterClaim() public {
        vm.prank(admin);
        airdrop.initAirdrop(user1);

        assertTrue(airdrop.hasClaimedAirdrop(user1), "User should have claimed after airdrop");
    }

    function test_HasClaimedAirdrop_IndependentPerUser() public {
        vm.prank(admin);
        airdrop.initAirdrop(user1);

        assertTrue(airdrop.hasClaimedAirdrop(user1), "User1 should have claimed");
        assertFalse(airdrop.hasClaimedAirdrop(user2), "User2 should not have claimed");
    }

    // ========================================
    // Integration Tests
    // ========================================

    function test_Integration_CompleteAirdropFlow() public {
        uint256 airdropAmount1 = 10 * 10 ** 6;
        uint256 airdropAmount2 = 15 * 10 ** 6;

        // Step 1: Admin airdrops to user1 with initial amount
        vm.prank(admin);
        airdrop.initAirdrop(user1);
        assertEq(facilitator.balanceOf(user1), airdropAmount1);

        // Step 2: Admin updates airdrop amount
        vm.prank(admin);
        airdrop.setAirdropAmount(airdropAmount2);

        // Step 3: Admin airdrops to user2 with new amount
        vm.prank(admin);
        airdrop.initAirdrop(user2);
        assertEq(facilitator.balanceOf(user2), airdropAmount2);

        // Step 4: Transfer admin rights
        address newAdmin = address(0x7);
        vm.prank(admin);
        airdrop.setAdmin(newAdmin);

        // Step 5: New admin airdrops to user3
        vm.prank(newAdmin);
        airdrop.initAirdrop(user3);
        assertEq(facilitator.balanceOf(user3), airdropAmount2);

        // Step 6: Verify all claims are recorded
        assertTrue(airdrop.hasClaimedAirdrop(user1));
        assertTrue(airdrop.hasClaimedAirdrop(user2));
        assertTrue(airdrop.hasClaimedAirdrop(user3));

        // Step 7: Verify double claims fail
        vm.prank(newAdmin);
        vm.expectRevert("Airdrop already claimed");
        airdrop.initAirdrop(user1);
    }

    function test_Integration_AirdropWithoutGranterRole() public {
        // Deploy new Airdrop without granting CREDIT_GRANTER_ROLE
        Airdrop newAirdrop = new Airdrop(admin, airdropInitiator, address(facilitator), AIRDROP_AMOUNT);

        // Airdrop should fail because Airdrop contract doesn't have role
        vm.prank(admin);
        vm.expectRevert("Not authorized to grant credits");
        newAirdrop.initAirdrop(user1);
    }

    function test_Integration_AirdropAfterRoleRevoked() public {
        bytes32 granterRole = facilitator.CREDIT_GRANTER_ROLE();

        // First airdrop succeeds
        vm.prank(admin);
        airdrop.initAirdrop(user1);
        assertEq(facilitator.balanceOf(user1), AIRDROP_AMOUNT);

        // Revoke role
        vm.prank(facilitatorOwner);
        facilitator.revokeRole(granterRole, address(airdrop));

        // Second airdrop should fail
        vm.prank(admin);
        vm.expectRevert("Not authorized to grant credits");
        airdrop.initAirdrop(user2);
    }

    // Events for testing
    event AirdropInitiated(address indexed receiver, uint256 amount);
    event AirdropAmountUpdated(uint256 previousAmount, uint256 newAmount);
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
}
