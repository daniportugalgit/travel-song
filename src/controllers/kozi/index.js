/*
This is a class that encapsulates the logic for fetching and processing new blocks from the blockchain.
In the future, it will fetch the price from the blockchain itself, but for now we'll just hardcode it.
*/

const BigNumber = require("bignumber.js");

const koziPrice = 10; // $10 is the target price for 1 kozi

function koziToStable(kozi) {
  return BigNumber(kozi).times(BigNumber(koziPrice)).toString();
}

function stableToKozi(stable) {
  return BigNumber(stable).div(BigNumber(koziPrice)).toString();
}

module.exports = {
  koziPrice,
  koziToStable,
  stableToKozi,
};
