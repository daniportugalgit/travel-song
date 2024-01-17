function shortHash(hash, initialDigits = 5, finalDigits = 4) {
  if (!hash) return null;

  const _finalDigits = 0 - finalDigits;

  if (finalDigits === 0) {
    return String(hash).slice(0, initialDigits);
  }

  return `${String(hash).slice(0, initialDigits)}...${String(hash).slice(_finalDigits)}`;
}

module.exports = {
  shortHash,
};
