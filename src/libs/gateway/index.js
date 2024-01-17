const Env = require("../../base/Env");
const requestIp = require("request-ip");
const { colors, print } = require("../../base/log");

class Gateway {
  constructor() {
    const operators = JSON.parse(Env.OPERATORS) || [];
    const discordOperators = JSON.parse(Env.DISCORD_OPERATORS) || [];

    this.operators = {};
    for (let i = 0; i < operators.length; i++) {
      const operator = operators[i];
      this.operators[operator.username] = operator.pass;
    }

    this.discordOperators = {};
    for (let i = 0; i < discordOperators.length; i++) {
      const discordOperator = discordOperators[i];
      this.discordOperators[discordOperator] = true;
    }

    this.validator = require("./validator");

    this.admin = Env.getString("ADMIN") || "";
  }

  isAllowedWithOpenCredentials(username, password) {
    if (!password || !username) return false;

    return password === this.operators[username];
  }

  isAllowed(req) {
    const username = req.headers["x-mh-username"];
    const password = req.headers["x-mh-code"];

    if (!password || !username) return false;

    return password === this.operators[username];
  }

  login(req) {
    if (this.isAllowed(req)) {
      const username = req.headers["x-mh-username"];
      print(colors.h_magenta, `User ${username} logged in as Operator`);
      return username;
    } else {
      const ip = requestIp.getClientIp(req);
      const path = req.baseUrl + req.path;
      throw new Error(`Unauthorized request from ${ip} to ${path}`);
    }
  }

  adminLogin(req) {
    const username = req.headers["x-mh-username"];

    if (this.isAllowed(req) && username === this.admin && this.admin !== "") {
      print(colors.h_green, `User ${username} logged in as ADMIN`);
      return username;
    } else {
      const ip = requestIp.getClientIp(req);
      const path = req.baseUrl + req.path;
      throw new Error(`Unauthorized ADMIN request from ${ip} to ${path}`);
    }
  }

  discordLogin(userTag) {
    if (this.discordOperators[userTag]) {
      print(colors.h_magenta, `Discord User ${userTag} logged in as Operator`);
      return userTag;
    } else {
      throw new Error(`Unauthorized Discord request from ${userTag}`);
    }
  }
}

module.exports = new Gateway();
