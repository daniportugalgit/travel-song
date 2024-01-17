const mongoose = require("mongoose");

/**
 * Finding the latest 25 transactions for an address:
 * db.transactions.find({
      $or: [
        { from: address },
        { to: address },
        { contractAddress: address },
        { eventEmitters: address }
      ]
    }).sort({ blockNumber: -1, transactionIndex: -1 }).limit(25);
 * 
 * Ordering by blocknumber and then by transactionindex:
 * db.transactions.find({query}).sort({ blockNumber: 1, transactionIndex: 1 });
 * */

function get() {
  return new mongoose.Schema({
    hash: String, // transaction hash
    blockNumber: Number, // block number of this transaction
    transactionIndex: Number, // index of this transaction in the block
    from: { type: String, index: true }, // sender
    to: { type: String, index: true }, // receiver
    contractAddress: { type: String, index: true }, // if this is a contract creation transaction
    eventEmitters: { type: Array, index: true }, // array of addresses that emitted events in this transaction
    status: Number, // 0 for failed, 1 for success
  });
}

module.exports = { get };
