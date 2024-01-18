const Env = require("../../base/Env");
const Mongo = require("../../libs/db/mongo");
const Fullnode = require("../Fullnode");
const { colors, print } = require("../../base/log");
const { ethers } = require("ethers");
//const Discord = require("../../libs/discord");

const POLLING_INTERVAL_MS = Env.getNumber("POLLING_INTERVAL_MS") || 10000;
const POLLING_SIZE = Env.getNumber("POLLING_SIZE") || 12;

/** Here's how this works:
  - Every 10 seconds, Travel Song Indexer (this app) will check for new blocks
  - If there are new blocks, it will query the RPC for all transactions receipts in those blocks
  - It will then index all transactions into the database
  - It will then check if there are more blocks to index
  - If there are, it will fetch the next block without waiting for the next 10 seconds
*/

class Crawler {
  async init() {
    this.isProcessingManyBlocks = false;
    await this.initPolling();
  }

  // This is the main loop of the crawler, we'll use it to poll the blockchain for new blocks
  async initPolling() {
    this.pollingInterval = setInterval(async () => {
      await this.onTick();
    }, POLLING_INTERVAL_MS);

    print(colors.h_black, `🎼 Polling: interval at ${POLLING_INTERVAL_MS} ms`);
  }

  // This is the where we actually check for new blocks
  async onTick() {
    // get the latest block number from the database
    const latestBlock = await Mongo.findOne("latestblocks", { chainId: 39916801 });
    const latestBlockNumber = latestBlock?.number || 0;
    const blockNumberToFetch = latestBlockNumber + 1;

    // get the latest block from the RPC
    print(colors.yellow, `🎼 Fetching Block ${blockNumberToFetch}...`);
    const rpcBlock = await Fullnode.fetchBlock(blockNumberToFetch);

    if (!rpcBlock || !rpcBlock.hash) {
      print(colors.red, `🎼 Block ${blockNumberToFetch} not found`);
      return;
    }

    print(colors.h_green, `🎼 Block ${blockNumberToFetch} fetched: ${rpcBlock.hash}`);
    await this.processBlock(rpcBlock);
  }

  // This is where we process the block data
  async processBlock(blockData) {
    const blockNumber = parseInt(blockData.number);
    //print(colors.h_cyan, `🎼 processBlock ${blockNumber}`);

    // we fetch all the transaction receipts from the RPC
    const txReceipts = await Promise.all(
      blockData.transactions.map((tx) => Fullnode.fetchTxReceipt(tx.hash))
    );

    // let's now process each receipt with the processReceipt function
    const processedReceipts = txReceipts.map((receipt) => this.processReceipt(receipt));

    // now we add the `input` and the `value` fields from the transaction to the receipt
    processedReceipts.forEach((receipt) => {
      const tx = blockData.transactions.find((tx) => tx.hash === receipt.hash);
      if (tx) {
        receipt.input = tx.input;
        receipt.value = tx.value;
      }
    });

    // now order the receipts by block number, then by transaction index (only if they're in the same block)
    processedReceipts.sort((a, b) => {
      if (a.blockNumber === b.blockNumber) {
        return a.transactionIndex - b.transactionIndex;
      }

      return a.blockNumber - b.blockNumber;
    });

    // now save all the receipts to the database:
    // we'll use the transactions collection
    // await Mongo.insertMany("transactions", processedReceipts);
    // actually, we will only add the receipts that have not been added yet
    //await Mongo.insertMany("transactions", processedReceipts);
    const bulkReceipts = [];
    processedReceipts.forEach(function (receipt) {
      bulkReceipts.push({
        updateOne: {
          filter: { hash: receipt.hash },
          update: { $set: receipt },
          upsert: true,
        },
      });
    });
    if (bulkReceipts.length > 0) {
      await Mongo.model("transactions").bulkWrite(bulkReceipts);
      print(colors.green, `🎼 Processed ${processedReceipts.length} receipts`);
    } else {
      //print(colors.cyan, `🎼 ZERO receipts inserted in database for block ${blockNumber}`);
    }

    // now save the latest block number to the database
    await Mongo.updateOne(
      "latestblocks",
      { chainId: 39916801 },
      { $set: { number: blockNumber } },
      { upsert: true }
    );

    if (this.isProcessingManyBlocks) {
      return; // we're already processing many blocks, so we'll skip the rest
    } else {
      let currentChainHeight = await Fullnode.blockNumber();
      currentChainHeight = parseInt(currentChainHeight);
      const blockNumberToFetch = blockNumber + 1;

      if (currentChainHeight > blockNumberToFetch && !this.isProcessingManyBlocks) {
        this.enterSyncMode(currentChainHeight, blockNumber);
      } else {
        if (!this.isProcessingManyBlocks) {
          // we're done
          print(colors.green, `🎼 Synced with block tip: ${blockNumberToFetch}`);
        }
      }
    }
  }

  async enterSyncMode(currentChainHeight, latesBlockProcessed) {
    print(
      colors.magenta,
      `🎼 Tip is ${currentChainHeight}. We're ${
        currentChainHeight - latesBlockProcessed
      } behind the tip. SYNC MODE ON!`
    );

    // we'll fetch the next 10 blocks, so let's clear the polling interval
    clearInterval(this.pollingInterval);

    const highestBlockToFetch = Math.min(currentChainHeight, latesBlockProcessed + POLLING_SIZE);
    const manyBlocks = await this.fetchManyBlocks(latesBlockProcessed + 1, highestBlockToFetch);

    // and we'll process it
    if (manyBlocks.length === 0) {
      print(colors.red, `🎼 Blocks not found`);
      return;
    }
    print(colors.h_green, `🎼 ${manyBlocks.length} Blocks fetched`);

    this.isProcessingManyBlocks = true;
    await this.processManyBlocks(manyBlocks);
    this.isProcessingManyBlocks = false;

    let newChainHeight = await Fullnode.blockNumber();
    newChainHeight = parseInt(newChainHeight);
    const nextBlockNumber = highestBlockToFetch + 1;

    if (newChainHeight > nextBlockNumber) {
      this.enterSyncMode(newChainHeight, highestBlockToFetch);
    } else {
      // we're done
      print(colors.green, `🎼 Synced with block tip: ${nextBlockNumber}`);

      // restart the polling interval:
      await this.initPolling();
    }
  }

  async fetchManyBlocks(startBlockNumber, endBlockNumber) {
    print(
      colors.yellow,
      `🎼 Fetching several blocks: from ${startBlockNumber} to ${endBlockNumber}...`
    );

    const promises = [];
    for (let i = startBlockNumber; i <= endBlockNumber; i++) {
      promises.push(Fullnode.fetchBlock(i));
    }

    const blocks = await Promise.all(promises);

    return blocks;
  }

  async processManyBlocks(blocks) {
    // we have to sort the blocks by block number
    blocks.sort((a, b) => {
      return a.number - b.number;
    });

    // now for each block, let's process it and await for it to finish (this will quickly skip empty blocks)
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      await this.processBlock(block);
    }
  }

  // This is where we process the transaction receipt: we add the eventEmitters to the object and return the object
  processReceipt(receiptData) {
    print(colors.magenta, `🎼 Processing receipt ${receiptData.transactionHash}`);

    // we'll create an object that has only the data we need
    // and we'll convert all the values

    const newReceiptData = {
      hash: receiptData?.transactionHash,
      blockNumber: parseInt(receiptData?.blockNumber),
      transactionIndex: parseInt(receiptData?.transactionIndex),
      from: "",
      to: "",
      contractAddress: "",
      eventEmitters: [],
      status: parseInt(receiptData?.status),
      input: receiptData?.input,
      value: receiptData?.value,
    };

    if (receiptData?.from) {
      newReceiptData.from = ethers.getAddress(receiptData.from);
    }

    if (receiptData?.to) {
      newReceiptData.to = ethers.getAddress(receiptData.to);
    }

    if (receiptData?.contractAddress) {
      newReceiptData.contractAddress = ethers.getAddress(receiptData.contractAddress);
    }

    if (receiptData?.logs) {
      newReceiptData.eventEmitters = receiptData.logs.map((log) => {
        try {
          return ethers.getAddress(log?.address);
        } catch (e) {}
      });
    }

    /*
    try {
      Discord.messageChannel(Discord.channels.travelSong, JSON.stringify(receiptData, null, 2));
    } catch (e) {
      print(colors.red, `🎼 Error sending receipt to Discord: ${e.message}`);
    }
    */

    return newReceiptData;
  }
}

module.exports = new Crawler();
