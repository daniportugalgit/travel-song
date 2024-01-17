const mongoose = require("mongoose");

/**
  This guy only has one field, number, which is the latest block number
  This collection only has one document, which is the latest block number
  The latest block number is updated every time we index a new block
 * */

function get() {
  return new mongoose.Schema({
    chainId: { type: Number, index: true },
    number: Number,
  });
}

module.exports = { get };
