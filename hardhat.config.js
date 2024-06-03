require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@nomicfoundation/hardhat-ignition");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          evmVersion: "london",
        },
      },
    ],
  },
  networks: {
    hardhat: {},
    coston: {
      url: "https://coston-api.flare.network/ext/bc/C/rpc",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 16,
    },
    songbird: {
      url: "https://songbird-api.flare.network/ext/bc/C/rpc",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 19,
    },
    coston2: {
      url: "https://coston2-api.flare.network/ext/bc/C/rpc",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 114,
    },
    flare: {
      url: "https://flare-api.flare.network/ext/bc/C/rpc",
      accounts: [process.env.PRIVATE_KEY],
      chainId: 14,
    },
  },
  etherscan: {
    apiKey: {
      coston2: "flare", // API key is not needed, but we need to provide a value
    },
    customChains: [
      {
        network: "coston2",
        chainId: 114,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/114/etherscan",
          browserURL: "https://coston2.testnet.flarescan.com",
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
