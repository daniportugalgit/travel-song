const dotenv = require("dotenv");
dotenv.config();

const { print, colors } = require("./log");

class Env {
  constructor() {
    const keys = Object.keys(process.env);
    const values = Object.values(process.env);

    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      this[key] = values[i];
    }

    // Log variables if they are listed to be logged
    if (this.LOG_VARIABLES) {
      const list = this.LOG_VARIABLES.split(",");
      print(colors.highlight, "||||||||||| Environment Variables |||||||||||");
      for (let i = 0; i < list.length; i++) {
        let color;
        if (this[list[i]] === "true") {
          color = colors.h_green;
        } else if (this[list[i]] === "false" || this[list[i]] === "" || !this[list[i]]) {
          color = colors.red;
        } else {
          color = colors.cyan;
        }

        print(color, `${list[i]}: ${this[list[i]]}`);
      }
      print(colors.highlight, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    }

    try {
      if (this?.DISCORD_ENV === "DEV") {
        this.DISCORD_TOKEN = this.DISCORD_TOKEN_DEV;
        this.DISCORD_CLIENT_ID = this.DISCORD_CLIENT_ID_DEV;
        print(colors.h_magenta, "[Env] Discord bot in DEV MODE");
      }
    } catch (e) {
      print(colors.h_red, "[Env] WARNING: discord bot DEV version not found!");
    }
  }

  getString(variableName) {
    return this[variableName] ?? "";
  }

  getBool(variableName) {
    if (this[variableName] == "false") return false;

    return !!this[variableName] ?? false;
  }

  getNumber(variableName) {
    return Number(this[variableName]) ?? 0;
  }

  getJson(variableName) {
    if (this[variableName]) {
      return JSON.parse(this[variableName]);
    } else {
      return {};
    }
  }
}

module.exports = new Env();
