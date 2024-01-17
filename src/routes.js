/**
 * In the future, we might want to hit the server to get info;
 * This routes.ts wiil be used for that
 */
const Env = require("./base/Env");
const { print, colors } = require("./base/log");

const { Router } = require("express");
const router = Router();

const controller = require("./controllers/main");

function setEndpoints() {
  const POST_ENDPOINTS = JSON.parse(Env.POST_ENDPOINTS);
  for (let i = 0; i < POST_ENDPOINTS.length; i++) {
    router.post(`/${POST_ENDPOINTS[i]}`, controller.parseRequest);
  }

  const GET_ENDPOINTS = JSON.parse(Env.GET_ENDPOINTS);
  for (let i = 0; i < GET_ENDPOINTS.length; i++) {
    router.get(`/${GET_ENDPOINTS[i]}`, controller.parseRequest);
  }

  print(colors.h_blue, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
  print(colors.h_blue, `Active endpoints:`);
  POST_ENDPOINTS.forEach((endpoint) => {
    print(colors.h_blue, `POST ➡  /${endpoint}`);
  });

  GET_ENDPOINTS.forEach((endpoint) => {
    print(colors.h_cyan, `GET ➡  /${endpoint}`);
  });

  print(colors.h_blue, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
}

setEndpoints();

module.exports = router;
