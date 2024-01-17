function extract(userAgentString) {
  let platform, version, comments;

  try {
    platform = userAgentString.split("/")[0];
  } catch (e) {
    platform = "";
  }

  try {
    version = userAgentString.split("/")[1].split("(")[0];
  } catch (e) {
    version = "";
  }

  try {
    comments = userAgentString.split("/")[1].split("(")[1].split(")")[0];
  } catch (e) {
    comments = "";
  }

  return {
    platform,
    version,
    comments,
  };
}

module.exports = { extract };
