# Siw3BoundNFT Contract Overview

This repository contains the Siw3BoundNFT contract – a soulbound, upgradeable ERC721 token with built-in supply management and role-based access control.

## Key Features

- **Soulbound Tokens:** Non-transferable tokens to enforce identity or achievement.
- **Upgradeable Design:** Uses UUPS proxy pattern for future upgrades.
- **Role-Based Access:** Roles for minting, increasing supply, and admin management.
- **Dynamic Supply Management:** Supports an initial mintable supply which can be increased (up to a capped maximum) via authorized roles.
- **Payment Processing:** Implements ETH payment handling with automatic refunds for any excess funds.
- **Membership Tiers:** Differentiates pricing between paid and free membership mints.

