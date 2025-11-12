// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IXRailFacilitator {
    function grantCredits(address grantee, uint256 amount) external;
}

/**
 * @title Airdrop
 * @notice Contract for managing credit airdrops to users
 * @dev Integrates with XRailFacilitator to grant credits
 */
contract Airdrop {
    // Admin who can manage airdrop settings
    address public admin;

    // Address authorized to initiate airdrops
    address public airdropInitiator;

    // XRailFacilitator contract reference
    IXRailFacilitator public facilitator;

    // Amount of credits to airdrop per user (stored with 6 decimals)
    uint256 public airdropAmount;

    // Tracking which addresses have already claimed airdrop
    mapping(address => bool) public hasClaimed;

    // Events
    event AirdropInitiated(address indexed receiver, uint256 amount);
    event AirdropAmountUpdated(uint256 previousAmount, uint256 newAmount);
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    event FacilitatorUpdated(address indexed previousFacilitator, address indexed newFacilitator);
    event AirdropInitiatorUpdated(address indexed previousInitiator, address indexed newInitiator);

    /**
     * @notice Contract constructor
     * @param _admin Address of the admin who can manage settings
     * @param _airdropInitiator Address authorized to initiate airdrops
     * @param _facilitator Address of the XRailFacilitator contract
     * @param _airdropAmount Initial amount of credits to airdrop per user
     */
    constructor(address _admin, address _airdropInitiator, address _facilitator, uint256 _airdropAmount) {
        require(_admin != address(0), "Invalid admin address");
        require(_airdropInitiator != address(0), "Invalid airdrop initiator address");
        require(_facilitator != address(0), "Invalid facilitator address");
        require(_airdropAmount > 0, "Airdrop amount must be positive");

        admin = _admin;
        airdropInitiator = _airdropInitiator;
        facilitator = IXRailFacilitator(_facilitator);
        airdropAmount = _airdropAmount;
    }

    /**
     * @notice Initiate airdrop for a receiver
     * @dev Only admin or airdropInitiator can call this function
     * @dev Prevents double claiming
     * @param receiver Address to receive the airdrop
     */
    function initAirdrop(address receiver) external {
        require(msg.sender == admin || msg.sender == airdropInitiator, "Not allowed to init Airdrop!");
        require(receiver != address(0), "Invalid receiver address");
        require(!hasClaimed[receiver], "Airdrop already claimed");

        // Mark as claimed before external call to prevent reentrancy
        hasClaimed[receiver] = true;

        // Grant credits through XRailFacilitator
        facilitator.grantCredits(receiver, airdropAmount);

        emit AirdropInitiated(receiver, airdropAmount);
    }

    /**
     * @notice Update the airdrop amount (admin only)
     * @param _newAmount New amount of credits to airdrop per user
     */
    function setAirdropAmount(uint256 _newAmount) external {
        require(msg.sender == admin, "Only admin can update airdrop amount");
        require(_newAmount > 0, "Airdrop amount must be positive");

        uint256 previousAmount = airdropAmount;
        airdropAmount = _newAmount;

        emit AirdropAmountUpdated(previousAmount, _newAmount);
    }

    /**
     * @notice Update the admin address (admin only)
     * @param _newAdmin New admin address
     */
    function setAdmin(address _newAdmin) external {
        require(msg.sender == admin, "Only admin can update admin");
        require(_newAdmin != address(0), "Invalid admin address");

        address previousAdmin = admin;
        admin = _newAdmin;

        emit AdminUpdated(previousAdmin, _newAdmin);
    }

    /**
     * @notice Update the facilitator address (admin only)
     * @param _newFacilitator New facilitator address
     */
    function setFacilitator(address _newFacilitator) external {
        require(msg.sender == admin, "Only admin can update facilitator");
        require(_newFacilitator != address(0), "Invalid facilitator address");

        address previousFacilitator = address(facilitator);
        facilitator = IXRailFacilitator(_newFacilitator);

        emit FacilitatorUpdated(previousFacilitator, _newFacilitator);
    }

    /**
     * @notice Update the airdrop initiator address (admin only)
     * @param _newInitiator New airdrop initiator address
     */
    function setAirdropInitiator(address _newInitiator) external {
        require(msg.sender == admin, "Only admin can update airdrop initiator");
        require(_newInitiator != address(0), "Invalid airdrop initiator address");

        address previousInitiator = airdropInitiator;
        airdropInitiator = _newInitiator;

        emit AirdropInitiatorUpdated(previousInitiator, _newInitiator);
    }

    /**
     * @notice Check if an address has already claimed airdrop
     * @param user Address to check
     * @return claimed Whether the address has claimed
     */
    function hasClaimedAirdrop(address user) external view returns (bool) {
        return hasClaimed[user];
    }
}
