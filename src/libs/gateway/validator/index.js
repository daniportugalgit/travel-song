class Validator {
  constructor() {
    this.endpoints = require("./endpoints");
  }

  acceptedParamsOf(endpoint) {
    return [...this.endpoints[endpoint].mandatory, ...this.endpoints[endpoint].optional];
  }

  validateReq(endpoint, req) {
    endpoint = this.endpoints[endpoint];
    if (!endpoint) throw new Error(`Unknown endpoint: /${endpoint}`);

    this.existsOrDie(req, endpoint.mandatory);
    this.paramsAcceptedOrDie(req, [...endpoint.mandatory, ...endpoint.optional], endpoint.disabled);
  }

  exists(req, paramName) {
    if (req.body[paramName]) {
      return true;
    } else {
      return false;
    }
  }

  existAll(req, paramList) {
    for (let i = 0; i < paramList.length; i++) {
      if (
        req.body[paramList[i]] === undefined ||
        req.body[paramList[i]] === "" ||
        req.body[paramList[i]] === null
      ) {
        return false;
      }
    }

    return true;
  }

  existsOrDie(req, paramList) {
    for (let i = 0; i < paramList.length; i++) {
      this.valueExistsOrDie(req, paramList[i]);
    }
  }

  valueExistsOrDie(req, paramName) {
    if (!req.body[paramName]) {
      throw new Error(`Mandatory parameter missing: ${paramName}`);
    }
  }

  hasExactValue(req, paramName, paramValue) {
    if (req.body[paramName] === paramValue) {
      return true;
    } else {
      return false;
    }
  }

  hasExactValueOrDie(req, paramName, paramValue) {
    if (req.body[paramName] !== paramValue) {
      throw new Error(`Unexpected parameter value: ${paramName} != ${paramValue}`);
    }
  }

  paramMatches(req, paramName, matchList) {
    let match = false;
    for (let i = 0; i < matchList.length; i++) {
      if (req.body[paramName] === matchList[i]) {
        match = true;
      }
    }

    return match;
  }

  paramMatchesOrDie(req, paramName, matchList) {
    for (let i = 0; i < matchList.length; i++) {
      if (req.body[paramName] === matchList[i]) {
        return true;
      }
    }

    throw new Error(`Unexpected value at ${paramName}`);
  }

  paramsAcceptedOrDie(req, acceptedList, disabledList = []) {
    const paramList = Object.keys(req.body);

    const unknownParams = [];
    for (let i = 0; i < paramList.length; i++) {
      const paramName = paramList[i];
      if (disabledList.includes(paramName)) {
        throw new Error(`Param temporarily disabled: ${paramName}`);
      }

      if (!acceptedList.includes(paramName)) {
        unknownParams.push(paramName);
      }
    }

    if (unknownParams.length > 0) {
      throw new Error(`Param not allowed: ${unknownParams.join(", ")}`);
    }
  }
}

module.exports = new Validator();
