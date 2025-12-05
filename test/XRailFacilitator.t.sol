// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {XRailFacilitator} from "../src/XRailFacilitator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock USDC with ERC-3009 support
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public constant DECIMALS = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    constructor() {
        // Mint initial supply to test accounts
        balanceOf[address(this)] = 1000000 * 10 ** DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // ERC-3009: transferWithAuthorization
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        require(block.timestamp > validAfter, "Authorization not yet valid");
        require(block.timestamp < validBefore, "Authorization expired");
        require(!_authorizationStates[from][nonce], "Authorization already used");

        // For testing, we skip signature verification
        // In production, this would verify the signature against from address

        _authorizationStates[from][nonce] = true;

        require(balanceOf[from] >= value, "Insufficient balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit AuthorizationUsed(from, nonce);
        emit Transfer(from, to, value);
    }
}

contract XRailFacilitatorTest is Test {
    XRailFacilitator public implementation;
    XRailFacilitator public facilitatorCredits;
    MockUSDC public usdc;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public recipient = address(0x4);
    address public airdropContract = address(0x5);
    address public unauthorizedUser = address(0x6);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Mint USDC to test users
        usdc.mint(user1, 1000000 * 10 ** 6); // 1M USDC
        usdc.mint(user2, 1000000 * 10 ** 6); // 1M USDC

        // Deploy implementation
        implementation = new XRailFacilitator();

        // Deploy proxy and initialize
        uint256 initialPrice = 10 ** 6; // 1 USDC (6 decimals)
        bytes memory initData = abi.encodeWithSelector(XRailFacilitator.initialize.selector, owner, initialPrice);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        facilitatorCredits = XRailFacilitator(address(proxy));

        // Set USDC address
        vm.prank(owner);
        facilitatorCredits.setUsdc(address(usdc));
    }

    function test_PricePerSettle() public view {
        // Test pricePerSettle returns 1 credit (10^6)
        uint256 price = facilitatorCredits.pricePerSettle();
        assertEq(price, 10 ** 6, "Price per settle should be 1 credit (10^6)");
    }

    function test_BuyCreditsViaSettle() public {
        uint256 amount = 10 * 10 ** 6; // 10 USDC

        // User1 buys credits via settle
        vm.startPrank(user1);

        // Prepare authorization for buying credits (to == address(this))
        bytes32 buyNonce = keccak256("buy_nonce_1");
        bytes memory buySignature = new bytes(65); // Mock signature

        facilitatorCredits.settle(
            user1,
            address(facilitatorCredits), // to == address(this) means buying credits
            amount,
            0, // validAfter
            block.timestamp + 1 hours, // validBefore
            buyNonce,
            buySignature
        );

        vm.stopPrank();

        // Check credit balance (amount - fee)
        uint256 fee = facilitatorCredits.pricePerSettle();
        uint256 expectedCredits = amount - fee; // 10 USDC - 1 USDC fee = 9 USDC worth of credits
        uint256 credits = facilitatorCredits.balanceOf(user1);
        assertEq(credits, expectedCredits, "User should have credits minus fee");
    }

    function test_SettlePayment() public {
        // First, buy credits
        uint256 buyAmount = 10 * 10 ** 6; // 10 USDC
        bytes32 buyNonce = keccak256("buy_nonce_2");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), buyAmount, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        uint256 creditsAfterBuy = facilitatorCredits.balanceOf(user1);

        // Now use settle for payment
        uint256 transferAmount = 100 * 10 ** 6; // 100 USDC
        bytes32 transferNonce = keccak256("transfer_nonce_1");
        bytes memory transferSignature = new bytes(65);

        // Call settle from external caller (relayer)
        vm.prank(address(0x5)); // Relayer address
        facilitatorCredits.settle(
            user1,
            recipient, // to != address(this) means normal payment
            transferAmount,
            0, // validAfter
            block.timestamp + 1 hours, // validBefore
            transferNonce,
            transferSignature
        );

        // Check that credit was deducted (1 credit fee)
        uint256 fee = facilitatorCredits.pricePerSettle();
        uint256 remainingCredits = facilitatorCredits.balanceOf(user1);
        assertEq(remainingCredits, creditsAfterBuy - fee, "User should have fee deducted");

        // Check that USDC was transferred to recipient
        assertEq(usdc.balanceOf(recipient), transferAmount, "Recipient should have received USDC");
    }

    function test_InsufficientCreditsForSettle() public {
        // Try to use settle without credits
        uint256 transferAmount = 100 * 10 ** 6;
        bytes32 transferNonce = keccak256("transfer_nonce_2");
        bytes memory transferSignature = new bytes(65);

        vm.expectRevert("Insufficient credits");
        facilitatorCredits.settle(
            user1, recipient, transferAmount, 0, block.timestamp + 1 hours, transferNonce, transferSignature
        );
    }

    function test_BuyCreditsMinimumAmount() public {
        // Try to buy credits with exactly the fee amount
        uint256 fee = facilitatorCredits.pricePerSettle();
        bytes32 buyNonce = keccak256("buy_min_amount");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), fee, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        // Should result in 0 credits (fee - fee)
        assertEq(facilitatorCredits.balanceOf(user1), 0, "User should have 0 credits after fee");
    }

    function test_BuyCreditsLessThanFee() public {
        // Try to buy credits with less than fee amount
        uint256 fee = facilitatorCredits.pricePerSettle();
        uint256 tooLow = fee - 1;
        bytes32 buyNonce = keccak256("buy_too_low");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        vm.expectRevert("Value must be at least fee");
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), tooLow, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );
    }

    function test_WithdrawRevenue() public {
        // First, user buys credits
        uint256 buyAmount = 100 * 10 ** 6; // 100 USDC
        bytes32 buyNonce = keccak256("buy_nonce_3");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), buyAmount, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        uint256 contractBalance = usdc.balanceOf(address(facilitatorCredits));
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        // Owner withdraws revenue
        vm.prank(owner);
        facilitatorCredits.withdrawRevenue();

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + contractBalance, "Owner should receive all revenue");
        assertEq(usdc.balanceOf(address(facilitatorCredits)), 0, "Contract should have 0 balance");
    }

    function test_GasComparison() public {
        // Setup: Buy credits for user1
        uint256 buyAmount = 10 * 10 ** 6;
        bytes32 buyNonce = keccak256("buy_nonce_gas");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), buyAmount, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        uint256 transferAmount = 100 * 10 ** 6; // 100 USDC

        // Test 1: Gas cost for settle (wrapped)
        bytes32 wrappedNonce = keccak256("wrapped_transfer");
        bytes memory wrappedSignature = new bytes(65);

        uint256 gasStartWrapped = gasleft();
        facilitatorCredits.settle(
            user1, recipient, transferAmount, 0, block.timestamp + 1 hours, wrappedNonce, wrappedSignature
        );
        uint256 gasUsedWrapped = gasStartWrapped - gasleft();

        // Test 2: Gas cost for plain transferWithAuthorization
        bytes32 plainNonce = keccak256("plain_transfer");
        bytes memory plainSignature = new bytes(65);

        uint256 gasStartPlain = gasleft();
        usdc.transferWithAuthorization(
            user1, recipient, transferAmount, 0, block.timestamp + 1 hours, plainNonce, plainSignature
        );
        uint256 gasUsedPlain = gasStartPlain - gasleft();

        // Calculate overhead
        uint256 overhead = gasUsedWrapped - gasUsedPlain;
        uint256 overheadPercentage = (overhead * 100) / gasUsedPlain;

        // Log results
        emit log_named_uint("Gas for settle (wrapped)", gasUsedWrapped);
        emit log_named_uint("Gas for plain transferWithAuthorization", gasUsedPlain);
        emit log_named_uint("Overhead (gas)", overhead);
        emit log_named_uint("Overhead (%)", overheadPercentage);

        // The overhead should be reasonable (credit deduction + external call)
        assertTrue(gasUsedWrapped > gasUsedPlain, "Wrapped version should use more gas");
        assertTrue(overhead < 100000, "Overhead should be reasonable (< 100k gas)");
    }

    function test_InitializeWithZeroAddress() public {
        // Deploy new implementation to test initialization
        XRailFacilitator newImplementation = new XRailFacilitator();

        // Deploy proxy with valid initialization
        uint256 initialPrice = 10 ** 6; // 1 USDC (6 decimals)
        bytes memory initData = abi.encodeWithSelector(XRailFacilitator.initialize.selector, owner, initialPrice);

        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), initData);
        XRailFacilitator newFacilitator = XRailFacilitator(address(proxy));

        // Expect revert when setting USDC to zero address
        vm.prank(owner);
        vm.expectRevert("Invalid USDC address");
        newFacilitator.setUsdc(address(0));
    }

    function test_Decimals() public view {
        assertEq(facilitatorCredits.DECIMALS(), 6, "Decimals should be 6");
    }

    function test_USDCGetter() public view {
        assertEq(facilitatorCredits.usdc(), address(usdc), "USDC getter should return correct address");
    }

    function test_SetUSDC() public {
        // Deploy a new mock USDC
        MockUSDC newUsdc = new MockUSDC();

        // Record the previous USDC address
        address previousUsdc = facilitatorCredits.usdc();

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit UsdcAddressUpdated(previousUsdc, address(newUsdc));

        // Owner updates USDC address
        vm.prank(owner);
        facilitatorCredits.setUsdc(address(newUsdc));

        // Verify USDC address was updated
        assertEq(facilitatorCredits.usdc(), address(newUsdc), "USDC address should be updated");
        assertNotEq(facilitatorCredits.usdc(), previousUsdc, "USDC address should differ from previous");
    }

    function test_SetUSDCWithZeroAddress() public {
        // Attempt to set USDC to zero address
        vm.prank(owner);
        vm.expectRevert("Invalid USDC address");
        facilitatorCredits.setUsdc(address(0));
    }

    function test_SetUSDCOnlyOwner() public {
        MockUSDC newUsdc = new MockUSDC();

        // Non-owner tries to update USDC
        vm.prank(user1);
        vm.expectRevert();
        facilitatorCredits.setUsdc(address(newUsdc));

        // Verify USDC wasn't changed
        assertEq(facilitatorCredits.usdc(), address(usdc), "USDC should not be changed by non-owner");
    }

    function test_MultipleSettlements() public {
        // Buy enough credits for multiple settlements
        uint256 buyAmount = 20 * 10 ** 6; // 20 USDC
        bytes32 buyNonce = keccak256("buy_multi");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), buyAmount, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        uint256 initialCredits = facilitatorCredits.balanceOf(user1);
        uint256 fee = facilitatorCredits.pricePerSettle();

        // Perform multiple settlements
        for (uint256 i = 0; i < 5; i++) {
            bytes32 nonce = keccak256(abi.encodePacked("transfer_", i));
            bytes memory signature = new bytes(65);

            vm.prank(address(0x5));
            facilitatorCredits.settle(user1, recipient, 10 * 10 ** 6, 0, block.timestamp + 1 hours, nonce, signature);
        }

        // Check credits were deducted correctly (5 settlements = 5 fees)
        uint256 finalCredits = facilitatorCredits.balanceOf(user1);
        assertEq(finalCredits, initialCredits - (fee * 5), "Should deduct 5 fees");
    }

    function test_BalanceOf() public {
        assertEq(facilitatorCredits.balanceOf(user1), 0, "Initial balance should be 0");

        // Buy credits
        uint256 buyAmount = 10 * 10 ** 6;
        bytes32 buyNonce = keccak256("buy_balance");
        bytes memory buySignature = new bytes(65);

        vm.prank(user1);
        facilitatorCredits.settle(
            user1, address(facilitatorCredits), buyAmount, 0, block.timestamp + 1 hours, buyNonce, buySignature
        );

        uint256 fee = facilitatorCredits.pricePerSettle();
        assertEq(facilitatorCredits.balanceOf(user1), buyAmount - fee, "Balance should be amount minus fee");
    }

    // ========================================
    // Access Control Tests
    // ========================================

    function test_GrantCredits_OwnerCanGrant() public {
        uint256 amount = 100 * 10 ** 6; // 100 credits

        // Owner grants credits to user1
        vm.prank(owner);
        facilitatorCredits.grantCredits(user1, amount);

        // Verify credits were granted
        assertEq(facilitatorCredits.balanceOf(user1), amount, "User should have granted credits");
    }

    function test_GrantCredits_UnauthorizedUserCannotGrant() public {
        uint256 amount = 100 * 10 ** 6;

        // Unauthorized user tries to grant credits
        vm.prank(unauthorizedUser);
        vm.expectRevert("Not authorized to grant credits");
        facilitatorCredits.grantCredits(user1, amount);

        // Verify no credits were granted
        assertEq(facilitatorCredits.balanceOf(user1), 0, "No credits should be granted");
    }

    function test_GrantCredits_GranterRoleCanGrant() public {
        uint256 amount = 50 * 10 ** 6;

        // Owner grants CREDIT_GRANTER_ROLE to airdropContract
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();
        vm.prank(owner);
        facilitatorCredits.grantRole(granterRole, airdropContract);

        // Verify role was granted
        assertTrue(facilitatorCredits.hasRole(granterRole, airdropContract), "Airdrop should have CREDIT_GRANTER_ROLE");

        // Airdrop contract grants credits to user1
        vm.prank(airdropContract);
        facilitatorCredits.grantCredits(user1, amount);

        // Verify credits were granted
        assertEq(facilitatorCredits.balanceOf(user1), amount, "User should have granted credits");
    }

    function test_GrantCredits_RevokedRoleCannotGrant() public {
        uint256 amount = 50 * 10 ** 6;
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();

        // Owner grants role
        vm.prank(owner);
        facilitatorCredits.grantRole(granterRole, airdropContract);

        // Airdrop grants credits successfully
        vm.prank(airdropContract);
        facilitatorCredits.grantCredits(user1, amount);
        assertEq(facilitatorCredits.balanceOf(user1), amount);

        // Owner revokes role
        vm.prank(owner);
        facilitatorCredits.revokeRole(granterRole, airdropContract);

        // Verify role was revoked
        assertFalse(facilitatorCredits.hasRole(granterRole, airdropContract), "Role should be revoked");

        // Airdrop tries to grant credits again - should fail
        vm.prank(airdropContract);
        vm.expectRevert("Not authorized to grant credits");
        facilitatorCredits.grantCredits(user2, amount);
    }

    function test_RoleManagement_OnlyAdminCanGrantRole() public {
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();

        // Non-admin tries to grant role
        vm.prank(user1);
        vm.expectRevert();
        facilitatorCredits.grantRole(granterRole, airdropContract);

        // Verify role was not granted
        assertFalse(facilitatorCredits.hasRole(granterRole, airdropContract), "Role should not be granted");
    }

    function test_RoleManagement_OnlyAdminCanRevokeRole() public {
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();

        // Owner grants role
        vm.prank(owner);
        facilitatorCredits.grantRole(granterRole, airdropContract);

        // Non-admin tries to revoke role
        vm.prank(user1);
        vm.expectRevert();
        facilitatorCredits.revokeRole(granterRole, airdropContract);

        // Verify role is still granted
        assertTrue(facilitatorCredits.hasRole(granterRole, airdropContract), "Role should still be granted");
    }

    function test_InitializeAccessControl_GrantsAdminRoleToOwner() public view {
        // Verify owner has DEFAULT_ADMIN_ROLE
        bytes32 adminRole = facilitatorCredits.DEFAULT_ADMIN_ROLE();
        assertTrue(facilitatorCredits.hasRole(adminRole, owner), "Owner should have DEFAULT_ADMIN_ROLE");
    }

    function test_InitializeAccessControl_Reinitializer() public {
        // Deploy new implementation
        XRailFacilitator newImplementation = new XRailFacilitator();

        // Deploy proxy WITHOUT calling AccessControl init (simulating old version)
        uint256 initialPrice = 10 ** 6;
        bytes memory initData = abi.encodeWithSelector(XRailFacilitator.initialize.selector, owner, initialPrice);

        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), initData);
        XRailFacilitator oldVersionProxy = XRailFacilitator(address(proxy));

        // Now simulate upgrade by calling initializeAccessControl
        vm.prank(owner);
        oldVersionProxy.initializeAccessControl();

        // Verify owner has DEFAULT_ADMIN_ROLE after upgrade
        bytes32 adminRole = oldVersionProxy.DEFAULT_ADMIN_ROLE();
        assertTrue(oldVersionProxy.hasRole(adminRole, owner), "Owner should have admin role after upgrade init");
    }

    function test_InitializeAccessControl_CanOnlyBeCalledOnce() public {
        // Deploy a fresh proxy to test reinitializer properly
        XRailFacilitator newImplementation = new XRailFacilitator();
        uint256 initialPrice = 10 ** 6;
        bytes memory initData = abi.encodeWithSelector(XRailFacilitator.initialize.selector, owner, initialPrice);

        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), initData);
        XRailFacilitator newProxy = XRailFacilitator(address(proxy));

        // First call to initializeAccessControl should work (reinitializer(2))
        vm.prank(owner);
        newProxy.initializeAccessControl();

        // Second call should revert
        vm.prank(owner);
        vm.expectRevert();
        newProxy.initializeAccessControl();
    }

    function test_GrantCredits_MultipleGranters() public {
        uint256 amount1 = 100 * 10 ** 6;
        uint256 amount2 = 50 * 10 ** 6;
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();

        address granter1 = address(0x7);
        address granter2 = address(0x8);

        // Owner grants role to multiple addresses
        vm.startPrank(owner);
        facilitatorCredits.grantRole(granterRole, granter1);
        facilitatorCredits.grantRole(granterRole, granter2);
        vm.stopPrank();

        // Both granters can grant credits
        vm.prank(granter1);
        facilitatorCredits.grantCredits(user1, amount1);

        vm.prank(granter2);
        facilitatorCredits.grantCredits(user1, amount2);

        // Verify total credits
        assertEq(facilitatorCredits.balanceOf(user1), amount1 + amount2, "User should have credits from both granters");
    }

    function test_GrantCredits_EmitsEvent() public {
        uint256 amount = 100 * 10 ** 6;

        // Note: grantCredits doesn't emit an event currently
        // This test documents the expected behavior if we add events later
        vm.prank(owner);
        facilitatorCredits.grantCredits(user1, amount);

        assertEq(facilitatorCredits.balanceOf(user1), amount);
    }

    function test_Integration_AirdropScenario() public {
        bytes32 granterRole = facilitatorCredits.CREDIT_GRANTER_ROLE();
        uint256 airdropAmount = 10 * 10 ** 6; // 10 credits per user

        // Step 1: Owner grants CREDIT_GRANTER_ROLE to airdrop contract
        vm.prank(owner);
        facilitatorCredits.grantRole(granterRole, airdropContract);

        // Step 2: Airdrop contract grants credits to multiple users
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = recipient;

        vm.startPrank(airdropContract);
        for (uint256 i = 0; i < recipients.length; i++) {
            facilitatorCredits.grantCredits(recipients[i], airdropAmount);
        }
        vm.stopPrank();

        // Step 3: Verify all users received credits
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(
                facilitatorCredits.balanceOf(recipients[i]), airdropAmount, "Each user should have airdrop credits"
            );
        }

        // Step 4: Users can use credits for settlements
        bytes32 nonce = keccak256("settlement_after_airdrop");
        bytes memory signature = new bytes(65);

        vm.prank(address(0x9)); // Relayer
        facilitatorCredits.settle(
            user1,
            recipient,
            50 * 10 ** 6, // 50 USDC transfer
            0,
            block.timestamp + 1 hours,
            nonce,
            signature
        );

        // Verify credit was deducted
        uint256 fee = facilitatorCredits.pricePerSettle();
        assertEq(
            facilitatorCredits.balanceOf(user1),
            airdropAmount - fee,
            "User1 should have credit deducted after settlement"
        );

        // Step 5: Owner revokes airdrop contract role
        vm.prank(owner);
        facilitatorCredits.revokeRole(granterRole, airdropContract);

        // Step 6: Airdrop contract can no longer grant credits
        vm.prank(airdropContract);
        vm.expectRevert("Not authorized to grant credits");
        facilitatorCredits.grantCredits(user1, airdropAmount);
    }

    // ========================================
    // UUPS Upgrade Tests
    // ========================================

    function test_UpgradeToNewImplementation() public {
        // Deploy new implementation
        XRailFacilitator newImplementation = new XRailFacilitator();

        // Owner can upgrade
        vm.prank(owner);
        facilitatorCredits.upgradeToAndCall(address(newImplementation), "");

        // Verify state is preserved after upgrade
        assertEq(facilitatorCredits.usdc(), address(usdc), "USDC address should be preserved");
        assertEq(facilitatorCredits.owner(), owner, "Owner should be preserved");
        assertEq(facilitatorCredits.pricePerSettle(), 10 ** 6, "Price should be preserved");
    }

    function test_UpgradeOnlyOwner() public {
        XRailFacilitator newImplementation = new XRailFacilitator();

        // Non-owner cannot upgrade
        vm.prank(user1);
        vm.expectRevert();
        facilitatorCredits.upgradeToAndCall(address(newImplementation), "");
    }

    function test_UpgradePreservesCredits() public {
        // Grant credits to user1
        uint256 credits = 100 * 10 ** 6;
        vm.prank(owner);
        facilitatorCredits.grantCredits(user1, credits);

        assertEq(facilitatorCredits.balanceOf(user1), credits);

        // Deploy and upgrade to new implementation
        XRailFacilitator newImplementation = new XRailFacilitator();
        vm.prank(owner);
        facilitatorCredits.upgradeToAndCall(address(newImplementation), "");

        // Credits should be preserved
        assertEq(facilitatorCredits.balanceOf(user1), credits, "Credits should be preserved after upgrade");
    }

    // Helper function for event testing
    event UsdcAddressUpdated(address indexed previousUsdc, address indexed newUsdc);
}
