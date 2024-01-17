const util = require("util");
const doExec = util.promisify(require("child_process").exec);

const { print, colors } = require("../../base/log");
const { lineToJson } = require("./dockerLineParser");

// too dangerous to expose
async function exec(command) {
  console.log("[SHELL COMMAND]", command);

  const { stdout, stderr } = await doExec(command).catch((e) => {
    throw e;
  });

  printStd(stdout, stderr, "exec");

  return { stdout, stderr };
}

// TODO comando Discord pra limpar todas as sessões
// TODO: region should be set in .env
async function startGameSession(
  sessionName = "session_1",
  port = 7777,
  region = "SOUTHAMERICA",
  isPrivateMatch = false,
  imageHash
) {
  let command = `docker run -d --name ${sessionName} -p ${port}:7777/udp -it ${imageHash} -region=${region} -name=${sessionName}`;
  command = isPrivateMatch ? `${command} -privatematch=true` : command;
  console.log("[SHELL COMMAND]", command);

  const { stdout, stderr } = await doExec(command).catch((e) => {
    throw e;
  });

  //printStd(stdout, stderr, "startGameSession");

  return { stdout, stderr };
}

async function getLogs(containerId) {
  const { stdout, stderr } = await doExec(`docker logs ${containerId}`);
  //printStd(stdout, stderr, `Container logs for ${containerId}`);

  return { stdout, stderr };
}

async function getSessionId(sessionName) {
  const { stdout, stderr } = await getLogs(sessionName);
  //printStd(stdout, stderr, "Get Session Id");

  const stringToSearch = "Successfully created session 'MyLocalSessionName' with ID ";

  let sessionId = "";
  try {
    sessionId = stdout.split(stringToSearch)[1].split("'")[1];
  } catch (e) {
    return getSessionId(sessionName);
  }

  return { stdout, stderr, sessionId };
}

async function endGameSession(sessionName) {
  const command = `docker stop ${sessionName}`;
  console.log("[SHELL COMMAND]", command);

  const { stdout, stderr } = await doExec(command).catch((e) => {
    throw e;
  });

  printStd(stdout, stderr, "End Game Session");

  return { stdout, stderr };
}

async function getStoppedContainers() {
  const { stdout, stderr } = await doExec(`docker ps -f status=exited`);
  return { stdout, stderr };
}

async function getActiveContainers() {
  const { stdout, stderr } = await doExec(`docker ps`);
  return { stdout, stderr };
}

async function getActiveSessions() {
  const { stdout, stderr } = await doExec(`docker container ls`);
  return { stdout, stderr };
}

async function countActiveSessions() {
  const { stdout, stderr } = await getActiveSessions();
  printStd(stdout, stderr, "Active Sessions");

  const activeSessionsLines = stdout.split("\n");
  const activeSessionsCount = activeSessionsLines.length - 2; // the first and last lines should be ignored
  print(colors.cyan, `Session Manager :: countActiveSessions :: ${activeSessionsCount}`);

  return activeSessionsCount;
}

async function info() {
  const { stdout, stderr } = await getAllContainers();
  printStd(stdout, stderr, "All Containers");

  const allContainersLines = stdout.split("\n");
  const containers = [];
  for (let i = 1; i < allContainersLines.length; i++) {
    if (allContainersLines[i].length > 1) {
      const json = lineToJson(allContainersLines[i]);
      containers.push(json);
    }
  }

  return containers;
}

async function getAllContainers() {
  const { stdout, stderr } = await doExec(`docker ps -a`);
  return { stdout, stderr };
}

async function stopAllInstances() {
  const activeSessions = await countActiveSessions();
  const containersNames = await getAllContainersNames();

  if (containersNames.length <= 1) {
    return { stdout: "No active sessions found", stderr: "" };
  }

  const command = `docker stop ${containersNames.join(" ")}`;
  console.log("[SHELL COMMAND]", command);

  const { stdout, stderr } = await doExec(command);
  return { stdout, stderr, instancesStopped: activeSessions };
}

async function clearStoppedInstances() {
  const { stdout, stderr } = await doExec(`docker rm $(docker ps -f status=exited -q)`);
  return { stdout, stderr };
}

async function pruneContainers() {
  const { stdout, stderr } = await doExec(`docker container prune --force`);
  return { stdout, stderr };
}

function printStd(stdout, stderr, title) {
  if (stderr) {
    print(colors.error, `${title}: ${stderr}`);
  } else {
    print(colors.success, `${title}: ${stdout}`);
  }
}

async function getAllContainersNames() {
  const { stdout, stderr } = await getAllContainers();
  printStd(stdout, stderr, "All Containers");

  const allContainersLines = stdout.split("\n");
  const containersNames = [];
  for (let i = 1; i < allContainersLines.length; i++) {
    const trimmedLine = allContainersLines[i]
      .split(" ")
      .filter((s) => s)
      .join(" ");

    const containerLineWords = trimmedLine.split(" ");
    const containerName = containerLineWords[containerLineWords.length - 1].trim();
    containersNames.push(containerName);
  }

  print(colors.cyan, `Session Manager :: getAllContainersNames :: ${containersNames}`);

  return containersNames;
}

async function killZombieSessions(activeList) {
  print(colors.cyan, `Session Manager killZombieSessions :: Active List: ${activeList}`);

  // First, prune stopped containers:
  const { stdout: pruneOut, stderr: pruneErr } = await pruneContainers();
  printStd(pruneOut, pruneErr, "Prune Containers");

  const containersNames = await getAllContainersNames();

  const containersToKill = containersNames
    .filter((containerName) => {
      return !activeList.includes(containerName);
    })
    .join(" ");

  print(colors.cyan, `Session Manager :: containersToKill :: ${containersToKill}`);

  if (containersToKill.length > 1) {
    const command = `docker stop ${containersToKill}`;
    console.log("[SHELL COMMAND]", command);

    const { stdout: out, stderr: err } = await doExec(command).catch((e) => {
      throw e;
    });

    console.log("> out:", out);
    console.log("> err:", err);

    const { stdout: clearOut, stderr: clearErr } = await clearStoppedInstances().catch((e) => {
      throw e;
    });

    console.log("> clearOut:", clearOut);
    console.log("> clearErr:", clearErr);

    if (err || clearErr) {
      throw new Error(`Session Manager :: clearStoppedInstances :: ${err} :: ${clearErr}`);
    }

    const totalInstancesDestroyed = Math.max(containersToKill.split(" ").length - 1, 0);
    return { result: `Sessions killed: ${containersToKill}`, totalInstancesDestroyed };
  } else {
    return { result: "No zombie sessions found", totalInstancesDestroyed: 0 };
  }
}

async function syncDockerImage(imageAddress) {
  const { stdout: deleteOut, stderr: deleteErr } = await deleteAllDockerImages();
  printStd(deleteOut, deleteErr, "Delete Local Images");

  print(colors.yellow, `Session Manager :: pulling image...`);
  const { stdout: pullOut, stderr: pullErr } = await doExec(`docker pull ${imageAddress}`);
  printStd(pullOut, pullErr, "Pull Image");

  const { stdout: listOut, stderr: listErr, images } = await listDockerImages();
  printStd(listOut, listErr, "List Images");

  print(colors.cyan, `Session Manager :: syncDockerImage :: imageHash :: ${images[0]}`);

  // return the image hash:
  return { stdout: pullOut, stderr: pullErr, imageHash: images[0] };
}

async function deleteAllDockerImages() {
  const { stdout: purgeOut, stderr: purgeErr, instancesStopped } = await purgeAll();
  printStd(purgeOut, purgeErr, "Stop Images");
  print(colors.cyan, `DeleteAllDockerImages :: instancesStopped :: ${instancesStopped}`);

  // find out how many images there are
  const { images } = await listDockerImages();
  if (images.length === 0 || images[0] === "" || images[0] === " ") {
    return { stdout: "No images found", stderr: "" };
  } else {
    print(colors.cyan, `DeleteAllDockerImages :: images :: ${images} (${images.length} images)`);
  }

  const { stdout: imagesOut, stderr: imagesErr } = await doExec(
    `docker rmi -f $(docker images -aq)`
  );

  return { stdout: imagesOut, stderr: imagesErr, instancesStopped };
}

async function dockerImageLs() {
  const { stdout, stderr } = await doExec(`docker image ls`);
  return { stdout, stderr };
}

async function listDockerImages() {
  const { stdout, stderr } = await dockerImageLs();

  const lines = stdout.split("\n");
  const images = [];
  for (let i = 1; i < lines.length; i++) {
    const trimmedLine = lines[i]
      .split(" ")
      .filter((s) => s)
      .join(" ");

    print(colors.yellow, `Session Manager :: listDockerImages :: trimmedLine :: ${trimmedLine}`);
    const image = trimmedLine.split(" ")[2];

    if (image && image !== "" && image !== " " && image !== "  ") {
      images.push(image);
    }
  }

  return { stdout, stderr, images };
}

async function purgeAll() {
  const { stdout: stopOut, stderr: stopErr, instancesStopped } = await stopAllInstances();
  printStd(stopOut, stopErr, "Stop Images");

  const { stdout: pruneOut, stderr: pruneErr } = await pruneContainers();
  printStd(pruneOut, pruneErr, "Prune Containers");

  return stopErr || pruneErr || { stdout: stopOut, pruneOut, instancesStopped };
}

module.exports = {
  startGameSession,
  endGameSession,
  killZombieSessions,
  getActiveContainers,
  getAllContainers,
  getAllContainersNames,
  stopAllInstances,
  countActiveSessions,
  getStoppedContainers,
  clearStoppedInstances,
  syncDockerImage,
  getLogs,
  getSessionId,
  deleteAllDockerImages,
  purgeAll,
  pruneContainers,
  listDockerImages,
  info,
};
