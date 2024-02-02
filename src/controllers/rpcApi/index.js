// Receives POSTs via the /rpc endpoint

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
    let addressList = await Mongo.model("balances")
      .find({ address: { $nin: [...SISTEM_WALLETS] } })
      .sort({ kozi: -1 })
      .collation({ locale: "en_US", numericOrdering: true })
      .limit(limit);

    // now let's cleanup the list removing the propertyes _id, __v, and updatedAtBlock
    addressList = addressList.map((address) => {
      return {
        address: address.address,
        kozi: address.kozi,
      };
    });

    const result = {
      success: true,
      addressList,
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
}

module.exports = new RpcApi();
