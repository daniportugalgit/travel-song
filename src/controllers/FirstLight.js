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

const transactionsSchema = require("../schemas/transaction"); // stores all transactions
const latestblocksSchema = require("../schemas/latestblock"); // saves the latest block number
const balancesSchema = require("../schemas/balance"); // saves the KOZI balances of all addresses

const { print, colors } = require("../base/log");

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

    this.initialized = true;

    print(colors.bigSuccess, "✨ First Light :: initialized");
  }
}

module.exports = new FirstLight();
