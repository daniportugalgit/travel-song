const Env = require("../base/Env");
const USE_TIMER = Env.getBool("USE_TIMER");

const { print, colors } = require("../base/log");

class Timer {
  constructor() {
    this.dictionary = {};
    this.printLog = true;
  }

  reset(name) {
    if (!USE_TIMER) return;

    this.dictionary[name] = {
      start: 0,
      end: 0,
    };
  }

  start(name) {
    if (!USE_TIMER) return;

    this.reset(name);
    this.dictionary[name].start = new Date().getTime();
  }

  // Prints and returns the elapsed time in seconds
  end(name) {
    if (!USE_TIMER) return;

    this.dictionary[name].end = new Date().getTime();
    const elapsed = (this.dictionary[name].end - this.dictionary[name].start) / 1000;

    if (this.printLog) {
      print(colors.h_black, `[Timer] ${name} executed in ${elapsed} seconds`);
    }

    return elapsed;
  }
}

module.exports = new Timer();
