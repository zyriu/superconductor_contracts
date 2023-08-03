require("@nomiclabs/hardhat-ethers");
require('hardhat-contract-sizer');
require('dotenv').config();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10
          }
        }
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10
          }
        }
      },
      {
        version: "0.6.11",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10
          }
        }
      }
    ],
    overrides: {
      "contracts/Factory.sol": {
        version: "0.5.16"
      },
      "contracts/Pair.sol": {
        version: "0.5.16"
      }
    }
  },
  networks: {
    base: {
      url: process.env.BASE_RPC,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 1000000000
    },
    base_goerli: {
      url: process.env.BASE_GOERLI_RPC,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 1000000000
    }
  }
}
