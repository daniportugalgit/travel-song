const { colors, print } = require("../base/log");
const Executor = require("./Executor");
const { extract } = require("../libs/gateway/userAgentExtractor");

const DEBUG_INCOMIG_TRAFFIC = true;

async function init() {
  await Executor.init();
}

async function parseRequest(req, res) {
  const path = String(req.path).replace("/", "");
  print(colors.cyan, `Incoming: ${req.path}\n${JSON.stringify(req.body, null, 2)}`);

  if (DEBUG_INCOMIG_TRAFFIC) {
    const userAgent = extract(req.headers["user-agent"]);
    print(colors.h_magenta, `🎼 -> UserAgent: ${JSON.stringify(userAgent, null, 2)}`);
  }

  try {
    const body = await Executor[path](req);

    if (body.success) {
      return onSuccess(res, body);
    } else {
      return onError(res, body);
    }
  } catch (e) {
    return onError(res, { success: false, message: e.stack });
  }
}

async function onSuccess(res, body) {
  //print(colors.green, `Outgoing body:${JSON.stringify(body, null, 2)}`);
  print(colors.green, `Returning success`);
  return res.status(200).json(body);
}

async function onError(res, body) {
  print(colors.red, `Error::Outgoing body:\n${JSON.stringify(body, null, 2)}`);
  return res.status(400).json(body);
}

module.exports = {
  init,
  parseRequest,
};
