const Env = require("../base/Env");
const { ethers } = require("ethers");
const { print, colors } = require("../base/log");
const State = require("../base/State");

const RPC_URL = Env.getString("RPC_URL");

function setupWeb3() {
  print(colors.yellow, "🌍 Setting up Ethers...");

  if (!RPC_URL) {
    print(colors.red, "❌ Skipping Blockchain module. Missing RPC_URL.");
    return;
  }

  State.provider = new ethers.JsonRpcProvider(RPC_URL);
  State.signer = new ethers.Wallet(Env.getString("PRIVATE_KEY"), State.provider);

  print(colors.green, `🌍 Ethers set up in ${Env.ENV}. Blockchain URL: ${RPC_URL}`);

  State.provider.on("error", (error) => {
    print(colors.red, `❌ Provider error (restarting): ${error.message}`);
    process.exit(1); // PM2 will restart the process
  });
}

module.exports = { setupWeb3 };
