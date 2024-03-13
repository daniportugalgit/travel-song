const Mongo = require("..//libs/db/mongo");
// const Discord = require("../libs/discord");

/** Here's how this works:
  - Every 10 seconds, Travel Song Indexer (this app) will check for new blocks
  - If there are new blocks, it will query the RPC for all transactions receipts in those blocks
  - It will then index all transactions into the database
    - Each transaction will be stored in the transactions collection
    - Each transaction will be linked to one or more addresses in the addresses collection (as sender, receiver, event emitter, or created contract)

  - The contracts collection will hold the ABIs and addresses of all contracts that we want to index, and that's an isolated service
*/

const Env = require("../base/Env");
const transactionsSchema = require("../schemas/transaction"); // stores all transactions
const latestblocksSchema = require("../schemas/latestblock"); // saves the latest block number
const balancesSchema = require("../schemas/balance"); // saves the KOZI balances of all addresses
const State = require("../base/State");
const { ethers } = require("ethers");
const { print, colors } = require("../base/log");

const RPC_URL = Env.getString("RPC_URL");

class FirstLight {
  constructor() {
    this.initialized = false;
  }

  async restart() {
    process.exit(1);
  }

  async init() {
    if (this.initialized) return;

    print(colors.h_blue, "✨ First Light :: initializing...");

    await Mongo.connect();
    await Mongo.setModel("transactions", transactionsSchema.get());
    await Mongo.setModel("latestblocks", latestblocksSchema.get());
    await Mongo.setModel("balances", balancesSchema.get());

    //await Discord.init();

    State.provider = new ethers.JsonRpcProvider(RPC_URL);
    State.signer = new ethers.Wallet(Env.getString("PRIVATE_KEY"), State.provider);
    print(colors.green, `🌍 Ethers set up in ${Env.ENV}. Blockchain URL: ${RPC_URL}`);

    State.provider.on("error", (error) => {
      print(colors.red, `❌ Provider error (restarting): ${error.message}`);
      process.exit(1); // PM2 will restart the process
    });

    this.initialized = true;

    print(colors.bigSuccess, "✨ First Light :: initialized");
  }
}

module.exports = new FirstLight();
