const ethers = require("ethers");

function codeBlock(message) {
  return `\`\`\`json\n${message}\`\`\``;
}

function getChecksumAddress(address) {
  if (address === "0x0000000000000000000000000000000000000000") return address;

  try {
    return ethers.getAddress(address);
  } catch (e) {
    console.log(`Bad checksum address: ${address} | ${e.message}`);
    return null;
  }
}

async function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatNumber(numberOrString) {
  return Intl.NumberFormat("en-US").format(Number(numberOrString));
}

// Inclusive!
function getDaysBetween(fromDate, toDate) {
  const fromDateD = new Date(fromDate);
  const toDateD = new Date(toDate);
  const diff = toDateD.getTime() - fromDateD.getTime();
  return Math.ceil(diff / (1000 * 3600 * 24));
}

module.exports = {
  codeBlock,
  getChecksumAddress,
  delay,
  formatNumber,
  getDaysBetween,
};
