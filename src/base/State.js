const Env = require("./Env");
const { print, colors } = require("./log");

class State {
  constructor() {
    print(colors.success, "State mounted");
  }

  mountDefaultAuthorizationHeader() {
    this.defaultAuthorizationHeader = {
      "Content-Type": "application/json",
      "x-ts-username": "TravelSong",
      "x-ts-code": Env.getString("TRAVEL_SONG_X_CODE"),
    };
  }
}

module.exports = new State();
