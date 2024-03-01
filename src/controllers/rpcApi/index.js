// Receives POSTs via the /rpc endpoint
const BigNumber = require("bignumber.js");

const Mongo = require("../../libs/db/mongo");
const { ethers } = require("ethers");

const Fullnode = require("../Fullnode");
const { print, colors } = require("../../base/log");
const { SISTEM_WALLETS } = require("../../config/systemWallets");

class RpcApi {
  async txsByAddress({ address, page = 1, limit = 25, includeEvents = false }) {
    try {
      address = ethers.getAddress(address);
      console.log(`🎼 txsByAddress ${address} | page: ${page} | limit: ${limit}`);
    } catch (e) {
      return {
        success: false,
        message: e.message,
      };
    }

    let totalCount, txList;

    if (includeEvents) {
      totalCount = await Mongo.count("transactions", {
        $or: [
          { from: address },
          { to: address },
          { contractAddress: address },
          { eventEmitters: address },
        ],
      });

      txList = await Mongo.model("transactions")
        .find({
          $or: [
            { from: address },
            { to: address },
            { contractAddress: address },
            { eventEmitters: address },
          ],
        })
        .sort({ blockNumber: -1, transactionIndex: -1 })
        .limit(limit)
        .skip((page - 1) * limit);
    } else {
      totalCount = await Mongo.count("transactions", {
        $or: [{ from: address }, { to: address }, { contractAddress: address }],
      });

      txList = await Mongo.model("transactions")
        .find({
          $or: [{ from: address }, { to: address }, { contractAddress: address }],
        })
        .sort({ blockNumber: -1, transactionIndex: -1 })
        .limit(limit)
        .skip((page - 1) * limit);
    }

    const currentBlockHeight = await Fullnode.blockNumber();

    const result = {
      success: true,
      txList,
      totalCount,
      currentBlockHeight,
    };

    return result;
  }

  async latestTxs({ limit = 10 }) {
    // we return the `limit` latest transactions
    const txList = await Mongo.model("transactions")
      .find({})
      .sort({ blockNumber: -1, transactionIndex: -1 })
      .limit(limit);

    const result = {
      success: true,
      txList,
    };

    return result;
  }

  async latestSummary({ limit = 10 }) {
    // here we'll get the latest block and the latest transactions
    const latestBlock = await Fullnode.fetchLatestBlock();

    let latestTxsResult;
    if (latestBlock.transactions.length >= limit) {
      latestTxsResult = [];
    } else {
      latestTxsResult = await this.latestTxs({ limit: limit - latestBlock.transactions.length });
    }

    const result = {
      success: true,
      block: latestBlock,
      txList: latestTxsResult.txList,
    };

    print(
      colors.green,
      `🎼 latestSummary | block: ${latestBlock.number} | txs: ${latestTxsResult.txList.length}`
    );

    return result;
  }

  async topAddresses(limit = 25) {
    let addresses = await Mongo.model("balances")
      .find({ address: { $nin: [...SISTEM_WALLETS] } })
      .sort({ kozi: -1 })
      .collation({ locale: "en_US", numericOrdering: true })
      .limit(limit);

    // for each address, let's fetch their kozi balance
    addresses = await Promise.all(
      addresses.map(async (address) => {
        const balance = await Fullnode.balanceOf(address.address);
        address.kozi = ethers.formatEther(balance);
        return address;
      })
    );

    // now let's cleanup the list removing the propertyes _id, __v, and updatedAtBlock
    addresses = addresses.map((address) => {
      return {
        address: address.address,
        kozi: address.kozi,
      };
    });

    // and reorder it by kozi (that is a BigNumber string with 256 bits)
    addresses = addresses.sort((a, b) => {
      return BigNumber(b.kozi).minus(BigNumber(a.kozi));
    });

    // now, let's remove any items that have kozi equal to "0.0"
    addresses = addresses.filter((address) => address.kozi !== "0.0" && address.kozi !== "0.00");

    // now return the 25 first:
    addresses = addresses.slice(0, 25);

    const result = {
      success: true,
      addresses,
    };

    return result;
  }

  async allAddresses(limit = 25) {
    const addressList = await Mongo.model("balances")
      .find({})
      .sort({ kozi: -1 })
      .collation({ locale: "en_US", numericOrdering: true })
      .limit(limit);

    const result = {
      success: true,
      addressList,
    };

    return result;
  }

  async resetDatabase() {
    print(colors.h_magenta, "RESETTING DATABASE...");

    // we'll remove all data from the database
    await Mongo.model("transactions").deleteMany({});
    await Mongo.model("latestblocks").deleteMany({});
    await Mongo.model("balances").deleteMany({});

    await Mongo.model("latestblocks").create({ chainId: 39916801, number: 0 });

    print(colors.h_magenta, "DATABASE SUCCESSFULLY RESET");
  }
}

module.exports = new RpcApi();
