const Validator = require("../libs/gateway/validator");
const FirstLight = require("./FirstLight");
const RpcApi = require("../controllers/rpcApi");
const Crawler = require("../controllers/Crawler");
//const Discord = require("../libs/discord");

class Executor {
  constructor() {}

  async init() {
    await FirstLight.init();
    await Crawler.init();
  }

  async rpc(req) {
    Validator.validateReq("rpc", req);

    const result = await RpcApi[req.body.method](req.body.params);

    return result;
  }

  /*
  async sendMessageInChannel(req) {
    const { channelId, message } = req.body;

    await Discord.messageChannel(channelId, message);

    return {
      success: true,
      data: "Message sent",
    };
  }
  */
}

module.exports = new Executor();
