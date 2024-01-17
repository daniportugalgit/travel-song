const Env = require("../../../base/Env");

const mongoose = require("mongoose");
const State = require("../../../base/State");

const { print, colors } = require("../../../base/log");

const MIN_LOG_LEVEL = 5;

class Mongo {
  constructor() {
    this.models = {};
    this.connection = null;
  }

  async connect() {
    if (!this.connection) {
      print(colors.yellow, "📀 Connecting to MongoDB...");

      this.connection = await mongoose.connect(Env.MONGO_URI, {
        useNewUrlParser: true,
      });

      State.mongoConnected = true;

      print(colors.green, `📀 MongoDB connection established`);
    }
  }

  async setModel(collection, schema) {
    print(colors.cyan, `📀 setModel for ${collection}`, MIN_LOG_LEVEL);

    await this.connect().catch((e) => {
      throw e;
    });

    if (!this.models[collection]) {
      this.models[collection] = this.connection.model(collection, schema);
    }
  }

  model(collection) {
    return this.models[collection];
  }

  async find(modelName, params, topX = false, topXProperty = "amount") {
    //print(colors.cyan, `📀 find() at collection ${modelName} (topX:${topX})`, MIN_LOG_LEVEL);

    const model = this.model(modelName);

    let result;
    if (topXProperty && topX) {
      const sortObj = {};
      sortObj[topXProperty] = -1;
      result = await model
        .find(params)
        .sort(sortObj)
        .collation({ locale: "en_US", numericOrdering: true })
        .limit(topX)
        .catch((e) => {
          throw e;
        });
    } else {
      result = await model.find(params).catch((e) => {
        throw e;
      });
    }

    return result;
  }

  async mongoFind({ modelName, params, sort = {}, limit = 0 }) {
    //print(colors.cyan, `📀 mongoFind() at collection ${modelName}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);

    const result = await model
      .find(params)
      .sort(sort)
      .limit(limit)
      .catch((e) => {
        throw e;
      });

    return result;
  }

  async findOne(modelName, params) {
    //print(colors.cyan, `📀 find() at collection ${modelName}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);

    const result = await model.findOne(params).catch((e) => {
      throw e;
    });

    return result;
  }

  async count(modelName, params) {
    //print(colors.cyan, `📀 find() at collection ${modelName}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);

    const result = await model.count(params).catch((e) => {
      throw e;
    });

    return result;
  }

  async insert(modelName, document, upsert = false) {
    print(colors.cyan, `📀 insert ${modelName}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);

    let result;

    if (upsert) {
      result = await model.findOneAndUpdate(document, document, { upsert: true }).catch((e) => {
        throw e;
      });
    } else {
      result = await model.create(document).catch((e) => {
        throw e;
      });
    }

    return result;
  }

  async insertMany(modelName, documentList) {
    print(colors.cyan, `📀 insert ${modelName}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);
    const result = await model.insertMany(documentList).catch((e) => {
      throw e;
    });

    return result;
  }

  async updateOne(modelName, findParams, updateParams) {
    //print(colors.cyan, `📀 update ${modelName}`, MIN_LOG_LEVEL);
    /*
    print(colors.cyan, `>> findParams: ${JSON.stringify(findParams, null, 2)}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>> updateParams: ${JSON.stringify(updateParams, null, 2)}`, MIN_LOG_LEVEL);
    */

    const model = this.model(modelName);

    const result = await model.updateOne(findParams, updateParams).catch((e) => {
      throw e;
    });

    return result;
  }

  async updateMany(modelName, findParams, updateParams) {
    //print(colors.cyan, `📀 updateMany ${modelName}`, MIN_LOG_LEVEL);
    /*
    print(colors.cyan, `>> findParams: ${JSON.stringify(findParams, null, 2)}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>> updateParams: ${JSON.stringify(updateParams, null, 2)}`, MIN_LOG_LEVEL);
    */

    const model = this.model(modelName);

    const result = await model.updateMany(findParams, updateParams).catch((e) => {
      throw e;
    });

    return result;
  }

  async deleteOne(modelName, findParams) {
    print(colors.cyan, `📀 delete from ${collection}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);
    const result = await model.deleteOne(findParams).catch((e) => {
      throw e;
    });

    return result;
  }

  async deleteMany(modelName, findParams) {
    print(colors.cyan, `📀 deleteMany ${modelName}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>>> findParams: ${JSON.stringify(findParams, null, 2)}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);
    const result = await model.deleteMany(findParams).catch((e) => {
      throw e;
    });

    return result;
  }

  /**
   * Tallies or finds documents in a collection.
   * @param {string} action :: count, sum, avg, min, max, and tally (this has all other actions within it)
   * @param {string} modelName :: the name of the model
   * @param {object} search :: the search parameters
   * @param {number} ranked :: the number of results to return
   * @param {string} field :: the field to make accounting on (ignored if ranked <= 0)
   * @returns
   */
  async search(action, modelName, search, ranked, field = "$amount") {
    print(colors.cyan, `📀 ${action} ${modelName} by ${field} | ranked = ${ranked}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>> search: ${JSON.stringify(search, null, 2)}`, MIN_LOG_LEVEL);

    // Actions "tally" and "find" have special flows; count is more efficient
    if (action === "tally") {
      return this.fullTally(modelName, search, ranked, field);
    } else if (action === "find") {
      return this.find(modelName, search, ranked, field);
    } else if (action === "count") {
      return this.count(modelName, search);
    }

    const { aggregation, mongoAggId } = this.buildAggregation(search);

    let aggStep = { $group: { _id: mongoAggId } };
    let aggField = {};
    if (action === "count") {
      aggField = { $sum: 1 };
    } else {
      aggField[`$${action}`] = { $toDecimal: field };
    }

    aggStep["$group"][action] = aggField;
    aggregation.push(aggStep);

    if (ranked) {
      this.setRankedAggregation(aggregation, ranked, action);
    }

    const result = await this.aggregate(modelName, aggregation);

    print(colors.highlight, `📀 result: ${JSON.stringify(result, null, 2)}`, MIN_LOG_LEVEL);

    return result[0][action] || "0";
  }

  async fullTally(modelName, search, ranked, field = "$amount") {
    print(colors.cyan, `📀 Tally ${modelName} by ${field} | ranked = ${ranked}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>> search: ${JSON.stringify(search, null, 2)}`, MIN_LOG_LEVEL);

    const { aggregation, mongoAggId } = this.buildAggregation(search);

    aggregation.push({
      $group: {
        _id: mongoAggId,
        count: { $sum: 1 },
        sum: { $sum: { $toDecimal: field } },
        avg: { $avg: { $toDecimal: field } },
        min: { $min: { $toDecimal: field } },
        max: { $max: { $toDecimal: field } },
      },
    });

    aggregation.push({
      $project: {
        _id: 0,
        name: "$_id",
        count: { $toInt: "$count" },
        sum: { $round: [{ $toDouble: "$sum" }, 2] },
        avg: { $round: [{ $toDouble: "$avg" }, 2] },
        min: { $round: [{ $toDouble: "$min" }, 2] },
        max: { $round: [{ $toDouble: "$max" }, 2] },
      },
    });

    if (ranked) {
      this.setRankedAggregation(aggregation, ranked);
    }

    return this.aggregate(modelName, aggregation);
  }

  buildAggregation(search, mongoAggId = "$name") {
    if (!search) {
      search = {};
    }

    if (Object.keys(search).length === 0) {
      mongoAggId = "";
    }

    return {
      aggregation: [{ $match: search }],
      mongoAggId,
    };
  }

  setRankedAggregation(aggregation, topX, field = "sum") {
    // These actions want to sort by sum
    if (field === "find" || field === "tally" || field === "count") {
      field = "sum";
    }

    const sortObj = {};
    sortObj["$sort"] = {};
    sortObj["$sort"][field] = -1;

    aggregation.push(sortObj);
    aggregation.push({ $limit: topX });
  }

  async aggregate(modelName, aggregation) {
    print(colors.cyan, `📀 aggregate ${modelName}`, MIN_LOG_LEVEL);
    print(colors.cyan, `>>> aggregation: ${JSON.stringify(aggregation, null, 2)}`, MIN_LOG_LEVEL);

    const model = this.model(modelName);
    const result = await model.aggregate(aggregation).catch((e) => {
      throw e;
    });

    return result;
  }
}

module.exports = new Mongo();
