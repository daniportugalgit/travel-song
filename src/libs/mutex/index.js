class Mutex {
  constructor() {
    this.locked = false;
  }

  lock() {
    this.locked = true;
  }

  unlock() {
    this.locked = false;
  }
}

module.exports = new Mutex();
