const Env = require("../../base/Env");
const RPC_URL = Env.getString("RPC_URL");

const axios = require("axios");

const { print, colors } = require("../../base/log");

class Fullnode {
  constructor() {
    this.currentBlockHeight = 0;
    this.blockHeightUpdatedAt = 0;
    this.blockContentsUpdatedAt = 0;
    this.latestBlock = null;
  }

  async _send(method, params) {
    const rpcObject = {
      method,
      params,
      id: 1,
      jsonrpc: "2.0",
    };

    //print(colors.h_blue, `Fullnode.SEND: ${JSON.stringify(rpcObject)}`);

    const rpcResponse = await axios.post(RPC_URL, rpcObject);

    return rpcResponse?.data?.result;
  }

  async fetchBlock(blockNumber) {
    const method = "eth_getBlockByNumber";
    const params = [blockNumber.toString(), true];

    return this._send(method, params);
  }

  async fetchLatestBlock(forceRefresh = false) {
    if (!forceRefresh && this.blockContentsUpdatedAt > Date.now() - 10000) {
      return this.latestBlock;
    }

    const method = "eth_getBlockByNumber";
    const params = ["latest", true];

    const result = await this._send(method, params);

    this.latestBlock = result;
    this.currentBlockHeight = parseInt(result.number, 16);
    this.blockHeightUpdatedAt = Date.now();
    this.blockContentsUpdatedAt = Date.now();

    return result;
  }

  async fetchTransaction(txHash) {
    const method = "eth_getTransactionByHash";
    const params = [txHash];

    return this._send(method, params);
  }

  async fetchTxReceipt(txHash) {
    const method = "eth_getTransactionReceipt";
    const params = [txHash];

    return this._send(method, params);
  }

  // we cache the block height for 10 seconds
  async blockNumber(forceRefresh = false) {
    if (!forceRefresh && this.blockHeightUpdatedAt > Date.now() - 10000) {
      return this.currentBlockHeight;
    }

    const method = "eth_blockNumber";
    const params = [];

    const result = await this._send(method, params);

    this.currentBlockHeight = parseInt(result, 16);
    this.blockHeightUpdatedAt = Date.now();

    return result;
  }

  async balanceOf(address) {
    const method = "eth_getBalance";
    const params = [address, "latest"];

    const result = await this._send(method, params);

    return result;
  }
}

module.exports = new Fullnode();
