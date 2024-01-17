const Env = require("../../base/Env");
const { print, colors } = require("../../base/log");

class SysQueue {
  constructor() {
    this.queue = [];
    this.processing = false;
    this.interval = Env.SYS_QUEUE_INTERVAL || 10; // milliseconds

    this.color = colors.cyan;
    this.h_color = colors.h_cyan;
    this.minLogLvl = 5;
  }

  /**
   * @dev Adds a function to the exectution queue.
   * @param {object} item { process: function, params: [] }
   */
  add(item) {
    print(this.color, `🎢 SysQueue::add(${JSON.stringify(item)})`, this.minLogLvl);

    this.queue.push(item);
    process();
  }

  isEmpty() {
    return this.queue.length === 0;
  }

  lock() {
    this.processing = true;
    print(this.h_color, `🎢 SysQueue::lock()`, this.minLogLvl);
  }

  unlock() {
    this.processing = false;
    print(this.h_color, `🎢 SysQueue::unlock()`, this.minLogLvl);
  }

  isLocked() {
    return this.processing;
  }

  async process() {
    if (this.isEmpty() || this.isLocked()) return;

    this.lock();

    const item = this.shift();
    print(this.color, `🎢 SysQueue::process(${JSON.stringify(item)})`, this.minLogLvl);

    await item.process.apply([...item.params]);

    this.unlock();

    setTimeout(this.process, this.interval);
  }
}

module.exports = new SysQueue();
