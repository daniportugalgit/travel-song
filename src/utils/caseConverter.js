function toSnakeCase(something) {
  if (Array.isArray(something)) {
    return arrayToSnakeCase(something);
  }

  switch (typeof something) {
    case "string":
      return stringToSnakeCase(something);
    case "object":
      return objectToSnakeCase(something);
    default:
      return null;
  }
}

function toCamelCase(something) {
  if (Array.isArray(something)) {
    return arrayToCamelCase(something);
  }

  switch (typeof something) {
    case "string":
      return stringToCamelCase(something);
    case "object":
      return objectToCamelCase(something);
    default:
      return null;
  }
}

function stringToSnakeCase(myString) {
  let newString = "";
  for (let i = 0; i < myString.length; i += 1) {
    newString +=
      (myString[i] === myString[i].toUpperCase() && i > 0 ? "_" : "") + myString[i].toLowerCase();
  }

  return newString;
}

function objectToSnakeCase(myObject) {
  if (!myObject) return {};

  try {
    const newObject = {};

    const keys = Object.keys(myObject);
    keys.forEach((key) => {
      const lowerCaseKey = stringToSnakeCase(key);
      newObject[lowerCaseKey] = myObject[key];

      if (
        typeof myObject[key] !== "string" &&
        typeof myObject[key] !== "number" &&
        typeof myObject[key] !== "boolean" &&
        typeof myObject[key] !== "undefined"
      ) {
        newObject[lowerCaseKey] = toSnakeCase(myObject[key]);
      }
    });

    return newObject;
  } catch (e) {
    console.log(`Unable to snake_case object: ${e}`);
    return myObject;
  }
}

function arrayToSnakeCase(myArray) {
  const newArray = [];
  for (let i = 0; i < myArray.length; i += 1) {
    const element = myArray[i];
    newArray.push(toSnakeCase(element));
  }

  return newArray;
}

function stringToCamelCase(myString) {
  return myString
    .split("_")
    .reduce(
      (res, word, i) =>
        i === 0
          ? word.toLowerCase()
          : `${res}${word.charAt(0).toUpperCase()}${word.substr(1).toLowerCase()}`,
      ""
    );
}

function objectToCamelCase(myObject) {
  const newObject = {};

  const keys = Object.keys(myObject);
  keys.forEach((key) => {
    const camelCaseKey = stringToCamelCase(key);
    newObject[camelCaseKey] = myObject[key];

    if (
      typeof myObject[key] !== "string" &&
      typeof myObject[key] !== "number" &&
      typeof myObject[key] !== "boolean" &&
      typeof myObject[key] !== "undefined"
    ) {
      newObject[camelCaseKey] = toCamelCase(myObject[key]);
    }
  });

  return newObject;
}

function arrayToCamelCase(myArray) {
  const newArray = [];
  for (let i = 0; i < myArray.length; i += 1) {
    const element = myArray[i];
    newArray.push(toCamelCase(element));
  }

  return newArray;
}

module.exports = { toSnakeCase, toCamelCase };
