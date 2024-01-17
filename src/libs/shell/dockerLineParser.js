//Index 0        Index 1        Index 2                  Index 3 (but now has many words)         Index 4 (many words)                        Index 5
//CONTAINER ID   IMAGE          COMMAND                  CREATED              STATUS              PORTS                                       NAMES
//9cad0aace67a   e860d5cb53e8   "/home/ue5/MouseHaun…"   About a minute ago   Up About a minute   0.0.0.0:7777->7777/udp, :::7777->7777/udp   session_1

function lineToJson(line) {
  const lineArray = trimToArray(line);

  console.log(`lineArray: ${lineArray.join("\n")}`);

  return {
    name: getName(lineArray),
    port: getPort(lineArray),
    status: getStatus(lineArray),
    containerId: getContainerId(lineArray),
  };
}

function trimToArray(line) {
  // Splits the string into an array of words
  const lineArray = line.split("   ").filter((s) => s);
  return lineArray;
}

function getName(trimmedArray) {
  return trimmedArray[trimmedArray.length - 1].trim();
}

// o campo PORTS pode estar vazio: significa que a sessão foi stoppada
function getPort(trimmedArray) {
  const bitToParse = trimmedArray[trimmedArray.length - 2];
  if (!bitToParse) return "None";
  if (bitToParse.includes("Exited")) return "None: session stopped";
  if (bitToParse === "") return "None: session stopped";

  //trimmedArray[line.length - 2] should equal "0.0.0.0:7777->7777/udp, :::7777->7777/udp"
  let port;
  try {
    port = trimmedArray[trimmedArray.length - 2].split(":")[1].split("->")[0];
  } catch (e) {
    port = "Error fetching port";
    console.log(e.stack);
  }

  return port;
}

function getStatus(trimmedArray) {
  return trimmedArray[4].trim();
}

function getContainerId(trimmedArray) {
  return trimmedArray[0].trim();
}

function getCreatedAt(trimmedArray) {
  return trimmedArray[3].trim();
}

module.exports = { lineToJson };
