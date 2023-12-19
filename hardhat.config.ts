import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-preprocessor";
import "hardhat-deploy";
import "hardhat-storage-layout-md";
import "hardhat-tracer";
import fs from "fs";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  namedAccounts: {
    deployer: 0,
    admin: 0,
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  paths: {
    artifacts: "./artifacts",
    sources: "./contracts",
    cache: "./cache_hardhat",
    newStorageLayoutPath: "./storage_layout",
  },
  networks: {
    hardhat: {
      accounts: {
        // only test
        mnemonic: process.env.MNEMONIC,
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 20,
      },
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    eg: {
      url: process.env.ETHEREUM_GOERLI_RPC_URL,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
      gasMultiplier: 2,
    },
    ag: {
      url: process.env.ARBITRUM_GOERLI_RPC_URL,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    as: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    og: {
      url: process.env.OPTIMISM_GOERLI_RPC_URL,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  etherscan: {
    apiKey: {
      arbitrumGoerli: process.env.ARBITRUM_API_KEY ?? "",
      optimisticGoerli: process.env.OPTIMISM_API_KEY ?? "",
      goerli: process.env.ETHEREUM_GOERLI_API_KEY ?? "",
    },
    customChains: [
      {
        network: "as",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
    ],
  },
  preprocess: {
    eachLine: (hre: any) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            // this matches all occurrences not just the start of import which could be a problem
            if (line.match(find)) {
              line = line.replace(find, replace);
            }
          });
        }
        return line;
      },
    }),
  },
};
function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean) // remove empty lines
    .map((line) => line.trim().split("="));
}

export default config;
