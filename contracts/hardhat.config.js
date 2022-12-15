require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config({ path: ".env" });

const AVAXFUJI_RPC_URL = process.env.AVAXFUJI_RPC_URL;

const AVAXFUJI_PRIVATE_KEY = process.env.AVAXFUJI_PRIVATE_KEY;

module.exports = {
  solidity: "0.8.17",
  networks: {
    avax_fuji: {
      url: AVAXFUJI_RPC_URL,
      accounts: [AVAXFUJI_PRIVATE_KEY],
    },
  },
};