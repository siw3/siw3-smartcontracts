// scripts/deploy-and-verify.js
const { ethers, upgrades, run } = require("hardhat");

async function main() {
  // Debug info
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log(
    "Account balance:",
    ethers.formatEther(await deployer.provider.getBalance(deployer.address)),
    "ETH"
  );
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network);

  // Load your contract factory
  const Siw3BoundNFT = await ethers.getContractFactory("Siw3BoundNFT");

  // Parameters for the contract initialization
  const name_ = "Siw3BoundNFT";
  const symbol_ = "SBNFT";

  // Admin & Minter roles
  const defaultAdmin = "defaultAdmin"; // Replace with actual admin address
  const minter = "minter"; // Replace with actual minter address
  // Add increase supply role address (user's wallet)
  const increaseSupplyRoleAddress = "supplyRole"; // Replace with actual user wallet

  // For the new contract we have two different supplies:
  //  - initialSupply: how many mints are immediately available
  //  - capSupply: the hard cap that cannot be exceeded
  const initialSupply = 50;
  const capSupply = 100;

  // Payment and membership details
  const platformWallet = "platformWallet"; // Replace with actual platform wallet
  const freeTierCost = ethers.parseEther("0.00012");
  const paidTierCost = ethers.parseEther("0.00006");
  const isPaidTier = true;

  // Calculate total cost = costPerNft * initialSupply
  const costPerNft = isPaidTier ? paidTierCost : freeTierCost;
  const totalValue = costPerNft * BigInt(initialSupply);

  console.log("Deployment parameters:", {
    name: name_,
    symbol: symbol_,
    defaultAdmin,
    minter,
    increaseSupplyRoleAddress, // Add to logs
    initialSupply,
    capSupply,
    platformWallet,
    freeTierCost: ethers.formatEther(freeTierCost),
    paidTierCost: ethers.formatEther(paidTierCost),
    isPaidTier,
    totalValue: ethers.formatEther(totalValue),
  });

  // 1) Deploy the proxy without calling initialize() immediately
  const proxy = await upgrades.deployProxy(Siw3BoundNFT, [], {
    kind: "uups",
    initializer: false,
  });
  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();
  console.log("Proxy deployed to:", proxyAddress);

  // 2) Manually call initialize with the correct 10 parameters + {value: totalValue}
  // function initialize(
  //   string memory name_,
  //   string memory symbol_,
  //   address admin,
  //   address minter,
  //   address increaseSupplyRoleAddress, // Add new parameter
  //   uint256 initialSupply_,
  //   uint256 capSupply_,
  //   address payable wallet,
  //   uint256 freeCost,
  //   uint256 paidCost,
  //   bool isPaid
  // ) public payable initializer
  const initTx = await proxy.initialize(
    name_,
    symbol_,
    defaultAdmin,
    minter,
    increaseSupplyRoleAddress, // Add new parameter
    initialSupply,
    capSupply,
    platformWallet,
    freeTierCost,
    paidTierCost,
    isPaidTier,
    { value: totalValue }
  );
  await initTx.wait();
  console.log("Contract initialized with value:", ethers.formatEther(totalValue));

  // 3) Retrieve the implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("Implementation at:", implAddress);

  // Optional: Wait for explorer indexing
  console.log("Waiting for explorer indexing...");
  await new Promise((resolve) => setTimeout(resolve, 60000));

  // 4) Verify on the block explorer (if supported on this network)
  try {
    console.log("Attempting verification...");
    await run("verify:verify", {
      address: implAddress,
      contract: "contracts/Siw3BoundNFT.sol:Siw3BoundNFT",
      constructorArguments: [],
      // Hardhat config for optimization
      optimizationUsed: true,
      runs: 200,
      evmVersion: "london",
    });
    console.log("Implementation verified successfully!");
  } catch (err) {
    console.error("Initial verification attempt failed:", err);
    // Optionally try Sourcify as a backup
    try {
      await run("sourcify", {
        address: implAddress,
        network: "network",
      });
      console.log("Contract verified via Sourcify!");
    } catch (sourcifyErr) {
      console.error("Sourcify verification also failed:", sourcifyErr);
    }
  }
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});
