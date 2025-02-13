import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";
import { resolve } from "path";

// Update dotenv config to use correct path
dotenv.config({ path: resolve(__dirname, ".env") });

// Validate environment variables
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BASE_API_KEY = process.env.BASE_API_KEY;

if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY not set in environment");
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.22",
    settings: {
      viaIR: true,  // <--- Enable the IR pipeline
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    BaseSepolia: {
      url: "https://sepolia.base.org/",
      chainId: 84532,
      accounts: [PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: BASE_API_KEY || "",
    customChains: [
      {
        network: "BaseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  }
};

export default config;
