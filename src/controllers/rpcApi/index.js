// Receives POSTs via the /rpc endpoint

const Mongo = require("../../libs/db/mongo");
const { ethers } = require("ethers");
const Fullnode = require("../Fullnode");

class RpcApi {
  async txsByAddress({ address, page = 1, limit = 25 }) {
    try {
      address = ethers.getAddress(address);
      console.log(`🎼 txsByAddress ${address} | page: ${page} | limit: ${limit}`);
    } catch (e) {
      return {
        success: false,
        message: e.message,
      };
    }

    // we count how many transactions there are for this address (collection "transactions)"
    const totalCount = await Mongo.count("transactions", {
      $or: [
        { from: address },
        { to: address },
        { contractAddress: address },
        //{ eventEmitters: address },
      ],
    });

    // then we return the transactions for this address considering the page and limit
    const txList = await Mongo.model("transactions")
      .find({
        $or: [
          { from: address },
          { to: address },
          { contractAddress: address },
          //{ eventEmitters: address },
        ],
      })
      .sort({ blockNumber: -1, transactionIndex: -1 })
      .limit(limit)
      .skip((page - 1) * limit);

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

    const currentBlockHeight = await Fullnode.blockNumber();

    const result = {
      success: true,
      txList,
      totalCount: txList.length,
      currentBlockHeight,
    };

    return result;
  }
}

module.exports = new RpcApi();
