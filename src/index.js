const Env = require("./base/Env");
const { print, colors } = require("./base/log");
const express = require("express");
const cors = require("cors");
const main = require("./controllers/main.js");

const PORT = Env.PORT;

const app = express();
app.options("*", cors());

app.get("/", (req, res) => res.send(`${Env.APP_NAME} online`));

app.use(express.json());
app.use(function (req, res, next) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});
app.use(require("./routes"));

app.listen(PORT, async () => {
  print(colors.h_green, `${Env.APP_NAME} API online at port ${PORT}`);
  start();
});

async function start() {
  await main.init();
}
