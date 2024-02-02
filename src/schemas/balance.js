const mongoose = require("mongoose");

function get() {
  return new mongoose.Schema({
    address: String, // user address
    kozi: String, // how much Kozi is in this account
    updatedAtBlock: Number, // block number of the latest update
  });
}

module.exports = { get };
