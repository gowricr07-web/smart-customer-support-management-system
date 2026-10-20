require("dotenv").config();
const neo4j = require("neo4j-driver");

const driver = neo4j.driver(
  process.env.NEO4J_URI || "neo4j://localhost:7687",
  neo4j.auth.basic(process.env.NEO4J_USER || "neo4j", process.env.NEO4J_PASSWORD || "password"),
  { disableLosslessIntegers: true }   // return plain JS numbers
);

// Run one query, return array of plain objects (one per record)
async function run(query, params = {}, write = false) {
  const session = driver.session();
  try {
    const res = write
      ? await session.executeWrite(tx => tx.run(query, params))
      : await session.executeRead(tx => tx.run(query, params));
    return res.records.map(r => r.toObject());
  } finally {
    await session.close();
  }
}

module.exports = { driver, run };
