// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract Siw3BoundNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant INCREASE_SUPPLY_ROLE = keccak256("INCREASE_SUPPLY_ROLE");
    /// @dev The absolute maximum supply we will ever allow.
    uint256 public capSupply;

    /// @dev The current supply that can be minted (initially set to initialSupply).
    ///      This value can be increased up to capSupply.
    uint256 public currentSupply;

    /// @dev The total number of tokens minted so far.
    uint256 public totalMinted;

    /// @dev Only used to store what was passed as the starting supply (for reference).
    uint256 public initialSupply;

    address payable public platformWallet;
    uint256 public freeTierCost;
    uint256 public paidTierCost;

    struct Member {
        uint96 prePaidMints; // Packed storage
        bool isPaidMember;
    }

    address public adminAddress; // Track single admin
    mapping(address => Member) public members;
    mapping(address => bool) public hasMinted;

    event PlatformFeesUpdated(uint256 free, uint256 paid);
    event PlatformWalletUpdated(address wallet);
    event FeesPaid(address admin, uint256 amount);
    event MembershipUpdated(address indexed admin, bool isPaid);

    /// @notice Emitted when the current supply is increased.
    event CurrentSupplyUpdated(uint256 newSupply);

    event Minted(address to, uint256 tokenId, string uri);

    /**
     * @param name_           Token name
     * @param symbol_         Token symbol
     * @param admin           Admin address (gets DEFAULT_ADMIN_ROLE)
     * @param minter          Minter address (gets MINTER_ROLE)
     * @param increaseSupplyRoleAddress User address (gets INCREASE_SUPPLY_ROLE)
     * @param initialSupply_  The initial supply to set as mintable
     * @param capSupply_      The maximum possible supply (cannot be exceeded)
     * @param wallet          The platform wallet to receive payments
     * @param freeCost        Cost per token for "free" membership
     * @param paidCost        Cost per token for "paid" membership
     * @param isPaid          Flag indicating if the admin is a paid member
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address admin,
        address minter,
        address increaseSupplyRoleAddress, // New Parameter
        uint256 initialSupply_,
        uint256 capSupply_,
        address payable wallet,
        uint256 freeCost,
        uint256 paidCost,
        bool isPaid
    ) public payable initializer {
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        adminAddress = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);

        // Grant INCREASE_SUPPLY_ROLE to the user
        _grantRole(INCREASE_SUPPLY_ROLE, increaseSupplyRoleAddress);

        require(capSupply_ > 0 && initialSupply_ > 0, "Invalid supply");
        require(initialSupply_ <= capSupply_, "Initial supply exceeds cap");
        require(wallet != address(0), "Invalid wallet");
        require(freeCost > 0 && paidCost > 0, "Invalid fees");

        initialSupply = initialSupply_;
        capSupply = capSupply_;
        currentSupply = initialSupply_;

        platformWallet = wallet;
        freeTierCost = freeCost;
        paidTierCost = paidCost;
        
        // Initialize admin membership info
        members[admin] = Member({
            prePaidMints: uint96(initialSupply_),
            isPaidMember: isPaid
        });

        // Charge the admin for all `initialSupply_` mints upfront at the correct cost per mint
        uint256 costPerMint = isPaid ? paidTierCost : freeTierCost;
        _processPayment(costPerMint * initialSupply_);
    }

    /**
     * @notice Update the free and paid tier costs.
     */
    function updatePlatformFees(uint256 _free, uint256 _paid) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_free > 0 && _paid > 0, "Invalid fees");
        freeTierCost = _free;
        paidTierCost = _paid;
        emit PlatformFeesUpdated(_free, _paid);
    }

    /**
     * @notice Update the platform wallet address.
     */
    function setPlatformWallet(address payable _wallet) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_wallet != address(0), "Invalid address");
        platformWallet = _wallet;
        emit PlatformWalletUpdated(_wallet);
    }

    /**
     * @notice Update a membership (paid or free).
     */
    function setPaidMembership(address admin, bool _isPaid) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        members[admin].isPaidMember = _isPaid;
        emit MembershipUpdated(admin, _isPaid);
    }
    /**
     * @notice Increase the current supply (paid by authorized users).
     * @dev Uses the admin's membership tier to calculate costs.
     * @param additionalMints The number of mints to add to the supply.
     */

    function increaseSupply(uint256 additionalMints) 
        external 
        payable 
        onlyRole(INCREASE_SUPPLY_ROLE) // Restrict to role holders
        nonReentrant 
    {
        require(additionalMints > 0, "Invalid amount");
        require(currentSupply + additionalMints <= capSupply, "Exceeds cap");

        // Always use the admin's membership data
        Member storage adminMember = members[adminAddress];

        // Calculate cost based on admin's tier
        uint256 costPer = adminMember.isPaidMember ? paidTierCost : freeTierCost;
        uint256 totalCost = costPer * additionalMints;

        // Process payment from the caller (user with the role)
        _processPayment(totalCost);

        // Update admin's state
        currentSupply += additionalMints;
        adminMember.prePaidMints += uint96(additionalMints);

        emit CurrentSupplyUpdated(currentSupply);
    }
    /**
     * @notice Mint a soulbound token.
     *         - Only allowed once per `to` address.
     *         - Must not exceed the current supply.
     */
    
    function mintSoulbound(address to, uint256 tokenId, string memory uri) 
        external 
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        require(!hasMinted[to], "Already minted");
        require(totalMinted < currentSupply, "Max supply reached");

        // Always check the admin's prePaidMints
        Member storage member = members[adminAddress];
        require(member.prePaidMints > 0, "No mints available");
        
        _mintSoulbound(to, tokenId, uri);
        member.prePaidMints--;
    }

    /**
     * @dev Internal soulbound mint helper.
     */
    function _mintSoulbound(address to, uint256 tokenId, string memory uri) private {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        hasMinted[to] = true;
        
        unchecked {
            totalMinted++;
        }
        emit Minted(to, tokenId, uri);
    }

    /**
     * @dev Handles ETH payments and refunds any excess.
     */
    function _processPayment(uint256 required) private {
        require(msg.value >= required, "Insufficient ETH");
        (bool sent, ) = platformWallet.call{value: required}("");
        require(sent, "Payment failed");
        
        uint256 excess = msg.value - required;
        if (excess > 0) {
            (sent, ) = msg.sender.call{value: excess}("");
            require(sent, "Refund failed");
        }
    }

    /**
     * @dev Soulbound enforcement. Reverts transfers except mint/burn.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("Soulbound: Transfers disabled");
        }
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Required for UUPS upgrade.
     */
    function _authorizeUpgrade(address) 
        internal 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {}

    /**
     * @dev Returns the token URI (metadata).
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Supports interface queries.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }       
}