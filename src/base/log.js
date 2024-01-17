const dotenv = require("dotenv");
dotenv.config();

/**
 * List of colors to be used in the `print` function
 */
const colors = {
  // simple font colors
  black: "\x1b[30m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  white: "\x1b[37m",

  // highlights
  h_black: "\x1b[40m\x1b[37m",
  h_red: "\x1b[41m\x1b[37m",
  h_green: "\x1b[42m\x1b[30m",
  h_yellow: "\x1b[43m\x1b[30m",
  h_blue: "\x1b[44m\x1b[37m",
  h_magenta: "\x1b[45m\x1b[37m",
  h_cyan: "\x1b[46m\x1b[30m",
  h_white: "\x1b[47m\x1b[30m",

  // aliases
  highlight: "\x1b[47m\x1b[30m", // white bg and black font
  error: "\x1b[41m\x1b[37m💥 ", // red bg, white font and explosion emoji
  success: "\x1b[32m✅ ", // green font and check emoji
  bigSuccess: "\x1b[42m\x1b[30m✅ ", // green bg, black font and check emoji
  warn: "\x1b[43m\x1b[30m📣 ", // yellow bg, black font and megaphone emoji
  wait: "\x1b[33m🕑 ", // yellow font and clock emoji

  // mandatory close
  close: "\x1b[0m",
};

/**
 * Prints a colored message on your console/terminal
 * @param {string} color Can be one of the above colors
 * @param {string} message Whatever string
 * @param {bool} breakLine Should it break line after the message?
 * @example print(colors.green, "something");
 */
function print(color, message, logLevel = 0, breakLine = false) {
  if (logLevel > process.env.LOG_LEVEL || 0) return;

  const lb = breakLine ? "\n" : "";
  console.log(`${color}${message}${colors.close}${lb}`);
}

module.exports = { colors, print };
